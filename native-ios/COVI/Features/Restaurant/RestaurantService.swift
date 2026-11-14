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
        guard !shop.archived, shop.kind == .restaurant, pin.isUnlocked, pin.unlockedStaffID == actor,
              admin || role == (kitchen ? .kitchen : .waiter) else { throw RestaurantFault.access }
        pin.touch()
    }
    func save() throws {
        do { try db.save() } catch { db.rollback(); throw error }
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
    func finish(_ table: DiningTable, order: CommerceOrder, paid: Bool) throws {
        try authorize()
        try check(table, order)
        guard table.billRequested == paid else { throw RestaurantFault.stale }
        if paid {
            let oid = order.id
            let lines = try db.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate { $0.orderID == oid }))
            guard lines.allSatisfy({ $0.preparation == Prep.served.rawValue }) else { throw RestaurantFault.stale }
            if order.totalMinor > 0 {
                db.insert(PaymentRecord(orderID: oid, establishmentID: shop.id, method: "Externe confirmé", amountMinor: order.totalMinor, confirmedByID: actor))
            }
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
