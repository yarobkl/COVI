import SwiftData
import Foundation

enum Prep: String, CaseIterable { case cooking = "En cuisine", ready = "Prêt", served = "Servi" }
enum MenuGroup: String, CaseIterable { case food = "Plats", drinks = "Boissons" }
enum RestaurantFault: LocalizedError {
    case access, stale, unavailable, invalid
    var errorDescription: String? {
        switch self {
        case .access: "Vérifiez le rôle et déverrouillez la caisse."
        case .stale: "La session ou le ticket a changé."
        case .unavailable: "Un article de la commande est en rupture."
        case .invalid: "Vérifiez les quantités et les montants."
        }
    }
}

@MainActor struct RestaurantService {
    let shop: Establishment
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    let db: ModelContext
    var admin: Bool { role == .owner || role == .manager }
    func authorize(kitchen: Bool = false) throws {
        guard !shop.archived, shop.kind == .restaurant, pin.mayOperate(shop: shop, actor: actor),
              admin || role == (kitchen ? .kitchen : .waiter) else { throw RestaurantFault.access }
        pin.touch()
    }
    func save() throws {
        do { try db.save() } catch { db.rollback(); throw error }
    }
    func editMenu(_ item: CatalogItem, title: String, price: Int64, category: MenuGroup) throws {
        try authorize()
        guard admin, item.establishmentID == shop.id,
              item.menuCategory != nil, price > 0 else { throw RestaurantFault.invalid }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw RestaurantFault.invalid }
        let sid = shop.id
        let peers = try db.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == sid
        }))
        guard !peers.contains(where: {
            $0.id != item.id && $0.menuCategory != nil &&
            $0.title.caseInsensitiveCompare(cleaned) == .orderedSame
        }) else { throw RestaurantFault.invalid }
        guard item.title != cleaned || item.priceMinor != price ||
              item.menuCategory != category.rawValue else { return }
        item.title = cleaned
        item.priceMinor = price
        item.menuCategory = category.rawValue
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.menu.edited", establishmentID: shop.id,
                entityID: item.id, actorID: actor, in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func editTable(_ table: DiningTable, label: String, capacity: Int) throws {
        try authorize()
        guard admin, table.establishmentID == shop.id, !table.isOccupied,
              table.activeSessionID == nil, (1...100).contains(capacity) else { throw RestaurantFault.stale }
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw RestaurantFault.invalid }
        let sid = shop.id
        let peers = try db.fetch(FetchDescriptor<DiningTable>(predicate: #Predicate {
            $0.establishmentID == sid
        }))
        guard !peers.contains(where: {
            $0.id != table.id && $0.label.caseInsensitiveCompare(cleaned) == .orderedSame
        }) else { throw RestaurantFault.invalid }
        guard cleaned != table.label || capacity != table.capacity else { return }
        table.label = cleaned
        table.capacity = capacity
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.table.edited", establishmentID: shop.id,
                entityID: table.id, actorID: actor, in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func open(_ table: DiningTable) throws {
        try authorize()
        guard table.establishmentID == shop.id, table.activeSessionID == nil, !table.isOccupied else { throw RestaurantFault.stale }
        let order = CommerceOrder(establishmentID: shop.id, createdByID: actor, tableID: table.id)
        order.state = .accepted
        table.activeSessionID = order.id
        table.isOccupied = true
        table.billRequested = false
        db.insert(order)
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.table.opened", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: [table.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func check(_ table: DiningTable, _ order: CommerceOrder) throws {
        guard table.establishmentID == shop.id, order.establishmentID == shop.id,
              order.tableID == table.id, table.activeSessionID == order.id, order.state == .accepted
        else { throw RestaurantFault.stale }
    }
    func send(_ basket: [UUID:Int], menu: [CatalogItem], table: DiningTable, order: CommerceOrder) throws {
        try authorize()
        try check(table, order)
        guard !table.billRequested, !basket.isEmpty else { throw RestaurantFault.stale }
        var total = order.totalMinor
        var lines: [OrderLine] = []
        for (id, count) in basket {
            guard let item = menu.first(where: { $0.id == id && $0.establishmentID == shop.id }),
                  !item.soldOut, MenuGroup(rawValue: item.menuCategory ?? "") != nil else { throw RestaurantFault.unavailable }
            let (amount, overflow) = item.priceMinor.multipliedReportingOverflow(by: Int64(count))
            let (next, exceeds) = total.addingReportingOverflow(amount)
            guard count > 0, item.priceMinor > 0, !overflow, !exceeds else { throw RestaurantFault.invalid }
            let line = OrderLine(orderID: order.id, catalogItemID: id, quantity: count, unitPriceMinor: item.priceMinor)
            line.dishName = item.title
            line.preparation = Prep.cooking.rawValue
            line.sentAt = .now
            lines.append(line)
            total = next
        }
        for line in lines { db.insert(line) }
        order.totalMinor = total
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.order.sent", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: lines.map { $0.id }, in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func advance(_ line: OrderLine, from expected: Prep, table: DiningTable, order: CommerceOrder) throws {
        try authorize(kitchen: expected == .cooking || role == .kitchen)
        try check(table, order)
        guard line.orderID == order.id, line.preparation == expected.rawValue, expected != .served else { throw RestaurantFault.stale }
        line.preparation = (expected == .cooking ? Prep.ready : Prep.served).rawValue
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.line.advanced", establishmentID: shop.id,
                entityID: line.id, actorID: actor, relatedIDs: [order.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func finish(_ table: DiningTable, order: CommerceOrder, paid: Bool,
                tender: Tender? = nil, received: Int64? = nil, confirmed: Bool = false) throws {
        try authorize()
        try check(table, order)
        guard table.billRequested == paid else { throw RestaurantFault.stale }
        if paid {
            guard let tender, order.totalMinor > 0,
                  (tender == .cash ? (received ?? -1) >= order.totalMinor : confirmed)
            else { throw RestaurantFault.invalid }
            let oid = order.id
            let lines = try db.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate { $0.orderID == oid }))
            let payments = try db.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.orderID == oid }))
            guard !lines.isEmpty, lines.allSatisfy({ $0.preparation == Prep.served.rawValue }),
                  payments.isEmpty else { throw RestaurantFault.stale }
            let payment = PaymentRecord(orderID: oid, establishmentID: shop.id, method: tender.rawValue,
                                        amountMinor: order.totalMinor, confirmedByID: actor)
            payment.cashReceived = tender == .cash ? received : nil
            db.insert(payment)
            order.state = .completed
            table.activeSessionID = nil
            table.isOccupied = false
        }
        table.billRequested = !paid
        do {
            try BusinessOutbox.enqueue(kind: paid ? "restaurant.order.paid" : "restaurant.bill.requested",
                establishmentID: shop.id, entityID: order.id, actorID: actor,
                relatedIDs: [table.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
}
