import SwiftData
import Foundation

enum Prep: String, CaseIterable {
    case received = "Reçu"
    case cooking = "En cuisine"
    case ready = "Prêt"
    case served = "Servi"

    var next: Prep? {
        switch self {
        case .received: .cooking
        case .cooking: .ready
        case .ready: .served
        case .served: nil
        }
    }
}
enum MenuGroup: String, CaseIterable { case food = "Plats", drinks = "Boissons" }

enum RestaurantDrinkBalance: Equatable {
    case untracked
    case tracked(Int)
    case invalid

    init(onHand: Int, reserved: Int, hasMovements: Bool) {
        if reserved < 0 || onHand < reserved {
            self = .invalid
        } else if hasMovements || onHand != 0 || reserved != 0 {
            self = .tracked(onHand - reserved)
        } else {
            self = .untracked
        }
    }
}

enum RestaurantFault: LocalizedError {
    case access, stale, unavailable, invalid, stock, balanceChanged, floorSlotOccupied, floorRoomName, guestCount
    case incidentReason, incidentExists
    var errorDescription: String? {
        switch self {
        case .access: "Vérifiez le rôle et déverrouillez la caisse."
        case .stale: "La session ou le ticket a changé."
        case .unavailable: "Un article de la commande est en rupture."
        case .invalid: "Vérifiez les quantités et les montants."
        case .stock: "Vérifiez le stock physique et les quantités réservées."
        case .balanceChanged: "Le reste dû a changé. Vérifiez le montant et confirmez de nouveau."
        case .floorSlotOccupied: "Cette case est occupée dans l’espace de destination. Choisissez une case libre."
        case .floorRoomName: "Saisissez un nom d’espace unique de 1 à 40 caractères."
        case .guestCount: "Le nombre de convives doit correspondre aux places disponibles à cette table."
        case .incidentReason: "Saisissez un motif de 1 à 240 caractères."
        case .incidentExists: "Un incident est déjà consigné pour cette ligne."
        }
    }
}

enum DrinkStockOperation: String, Identifiable {
    case restock = "Réassort"
    case loss = "Casse ou perte"

    var id: Self { self }
    var movementReason: String {
        switch self {
        case .restock: "Réassort boisson"
        case .loss: "Casse ou perte boisson"
        }
    }
}

enum RestaurantBill {
    @MainActor
    static func remaining(_ order: CommerceOrder, payments: [PaymentRecord]) -> Int64? {
        var due = order.totalMinor
        guard due >= 0 else { return nil }
        var recorded = Set<UUID>()
        for payment in payments where payment.orderID == order.id {
            guard recorded.insert(payment.id).inserted, payment.establishmentID == order.establishmentID, payment.amountMinor > 0,
                  payment.amountMinor <= due else { return nil }
            due -= payment.amountMinor
        }
        return due
    }

    @MainActor
    static func checkoutBalance(_ order: CommerceOrder, lines: [OrderLine],
                                payments: [PaymentRecord]) throws -> Int64 {
        guard !lines.isEmpty, lines.allSatisfy({ $0.preparation == Prep.served.rawValue }),
              order.discountMinor >= 0 else { throw RestaurantFault.stale }
        var subtotal: Int64 = 0
        for line in lines {
            let (value, invalid) = line.unitPriceMinor.multipliedReportingOverflow(by: Int64(line.quantity))
            let (next, overflow) = subtotal.addingReportingOverflow(value)
            guard line.quantity > 0, line.unitPriceMinor > 0, !invalid, !overflow
            else { throw RestaurantFault.invalid }
            subtotal = next
        }
        guard order.discountMinor <= subtotal, subtotal - order.discountMinor == order.totalMinor,
              let due = remaining(order, payments: payments) else { throw RestaurantFault.balanceChanged }
        return due
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
        guard shop.kind == .restaurant,
              try StaffAccess.role(for: actor, in: shop, context: db) == role,
              admin || role == (kitchen ? .kitchen : .waiter),
              pin.mayOperate(shop: shop, actor: actor) else { throw RestaurantFault.access }
        pin.touch()
    }
    func save() throws {
        do { try db.save() } catch { db.rollback(); throw error }
    }
    func createMenuItem(title: String, price: Int64, category: MenuGroup) throws {
        try authorize()
        guard admin else { throw RestaurantFault.access }
        let name = try validMenuTitle(title, price: price)
        let item = CatalogItem(establishmentID: shop.id, title: name, priceMinor: price)
        item.menuCategory = category.rawValue
        db.insert(item)
        try saveMenuChange("restaurant.menu.created", item: item)
    }

    func editMenu(_ item: CatalogItem, title: String, price: Int64, category: MenuGroup) throws {
        try authorize()
        guard admin, item.establishmentID == shop.id, item.menuCategory != nil
        else { throw RestaurantFault.access }
        let name = try validMenuTitle(title, price: price, ignoring: item.id)
        guard item.menuCategory != MenuGroup.drinks.rawValue || category == .drinks || item.stockReserved == 0 else {
            throw RestaurantFault.stock
        }
        guard name != item.title || price != item.priceMinor || category.rawValue != item.menuCategory else { return }
        item.title = name
        item.priceMinor = price
        item.menuCategory = category.rawValue
        try saveMenuChange("restaurant.menu.edited", item: item)
    }

    func setMenuAvailability(_ item: CatalogItem, available: Bool) throws {
        try authorize()
        guard admin, item.establishmentID == shop.id, item.menuCategory != nil
        else { throw RestaurantFault.access }
        guard item.soldOut == available else { return }
        item.soldOut = !available
        try saveMenuChange("restaurant.menu.availability-changed", item: item)
    }

    func adjustDrinkStock(_ item: CatalogItem, operation: DrinkStockOperation, quantity: Int) throws {
        try authorize()
        guard admin, item.establishmentID == shop.id, item.menuCategory == MenuGroup.drinks.rawValue
        else { throw RestaurantFault.access }
        guard quantity > 0 else { throw RestaurantFault.invalid }

        let delta = operation == .restock ? quantity : -quantity
        let (next, overflow) = item.stockOnHand.addingReportingOverflow(delta)
        guard !overflow, item.stockReserved >= 0, item.stockOnHand >= item.stockReserved,
              next >= item.stockReserved else { throw RestaurantFault.stock }

        let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: delta, reason: operation.movementReason, actorID: actor)
        db.insert(movement)
        item.stockOnHand = next
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.drink-stock.adjusted", establishmentID: shop.id,
                entityID: item.id, actorID: actor, relatedIDs: [movement.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }

    private func validMenuTitle(_ title: String, price: Int64, ignoring existingID: UUID? = nil) throws -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, price > 0 else { throw RestaurantFault.invalid }
        let shopID = shop.id
        let peers = try db.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == shopID
        }))
        guard !peers.contains(where: {
            $0.id != existingID && $0.menuCategory != nil &&
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }) else { throw RestaurantFault.invalid }
        return name
    }

    private func saveMenuChange(_ event: String, item: CatalogItem) throws {
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: event, establishmentID: shop.id,
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
    @discardableResult
    func open(_ table: DiningTable, guestCount: Int? = nil) throws -> CommerceOrder {
        try authorize()
        guard table.establishmentID == shop.id, table.activeSessionID == nil, !table.isOccupied else { throw RestaurantFault.stale }
        if let guestCount { try validateGuests(guestCount, at: table) }
        let order = CommerceOrder(establishmentID: shop.id, createdByID: actor, tableID: table.id)
        order.restaurantGuestCount = guestCount
        order.state = .accepted
        table.activeSessionID = order.id
        table.isOccupied = true
        table.billRequested = false
        db.insert(order)
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.table.opened", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: [table.id], in: db)
            try save()
            return order
        } catch { db.rollback(); throw error }
    }
    func confirmGuests(_ count: Int, at table: DiningTable, order: CommerceOrder) throws {
        try authorize()
        try check(table, order)
        guard !table.billRequested else { throw RestaurantFault.stale }
        try validateGuests(count, at: table)
        guard order.restaurantGuestCount != count else { return }
        order.restaurantGuestCount = count
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.order.guests-confirmed", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: [table.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }

    private func validateGuests(_ count: Int, at table: DiningTable) throws {
        guard count > 0, count <= 100, count <= table.capacity else { throw RestaurantFault.guestCount }
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
        var reservations: [(item: CatalogItem, count: Int)] = []
        for (id, count) in basket {
            guard let item = menu.first(where: { $0.id == id && $0.establishmentID == shop.id }),
                  !item.soldOut, MenuGroup(rawValue: item.menuCategory ?? "") != nil else { throw RestaurantFault.unavailable }
            let (amount, overflow) = item.priceMinor.multipliedReportingOverflow(by: Int64(count))
            let (next, exceeds) = total.addingReportingOverflow(amount)
            guard count > 0, item.priceMinor > 0, !overflow, !exceeds else { throw RestaurantFault.invalid }
            let line = OrderLine(orderID: order.id, catalogItemID: id, quantity: count, unitPriceMinor: item.priceMinor)
            line.dishName = item.title
            line.preparation = Prep.received.rawValue
            line.sentAt = .now
            if item.menuCategory == MenuGroup.drinks.rawValue {
                switch try drinkBalance(item) {
                case .tracked(let available):
                    guard count <= available else { throw RestaurantFault.stock }
                    line.restaurantUsesDrinkStock = true
                    reservations.append((item, count))
                case .invalid:
                    throw RestaurantFault.stock
                case .untracked:
                    break
                }
            }
            lines.append(line)
            total = next
        }
        for entry in reservations {
            entry.item.stockReserved += entry.count
            entry.item.updatedAt = .now
        }
        for line in lines { db.insert(line) }
        order.totalMinor = total
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.order.sent", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: lines.map { $0.id }, in: db)
            try save()
        } catch { db.rollback(); throw error }
    }

    private func drinkBalance(_ item: CatalogItem) throws -> RestaurantDrinkBalance {
        if item.stockOnHand != 0 || item.stockReserved != 0 {
            return RestaurantDrinkBalance(onHand: item.stockOnHand, reserved: item.stockReserved, hasMovements: false)
        }
        let itemID = item.id
        let shopID = shop.id
        let hasMovements = try db.fetchCount(FetchDescriptor<StockMovement>(predicate: #Predicate {
            $0.itemID == itemID && $0.establishmentID == shopID
        })) > 0
        return RestaurantDrinkBalance(onHand: 0, reserved: 0, hasMovements: hasMovements)
    }
    func advance(_ line: OrderLine, from expected: Prep, table: DiningTable, order: CommerceOrder) throws {
        try advance([line], from: expected, table: table, order: order)
    }

    func advance(_ lines: [OrderLine], from expected: Prep, table: DiningTable, order: CommerceOrder) throws {
        try authorize(kitchen: expected == .received || expected == .cooking || role == .kitchen)
        try check(table, order)
        guard let next = expected.next, !lines.isEmpty, Set(lines.map(\.id)).count == lines.count,
              lines.allSatisfy({ $0.orderID == order.id && $0.preparation == expected.rawValue })
        else { throw RestaurantFault.stale }

        do {
            for line in lines {
                var related = [order.id]
                if next == .served, line.restaurantUsesDrinkStock == true {
                    let movementID = try consumeReservedDrink(line)
                    related.append(movementID)
                }
                line.preparation = next.rawValue
                try BusinessOutbox.enqueue(kind: expected == .received ? "restaurant.line.claimed" : "restaurant.line.advanced",
                    establishmentID: shop.id,
                    entityID: line.id, actorID: actor, relatedIDs: related, in: db)
            }
            try save()
        } catch { db.rollback(); throw error }
    }

    private func consumeReservedDrink(_ line: OrderLine) throws -> UUID {
        let itemID = line.catalogItemID
        let shopID = shop.id
        guard line.quantity > 0,
              let drink = try db.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
                  $0.id == itemID && $0.establishmentID == shopID
              })).first,
              drink.menuCategory == MenuGroup.drinks.rawValue,
              drink.stockReserved >= line.quantity, drink.stockOnHand >= drink.stockReserved else {
            throw RestaurantFault.stock
        }
        let movementID = line.id
        guard try db.fetchCount(FetchDescriptor<StockMovement>(predicate: #Predicate {
            $0.id == movementID
        })) == 0 else { throw RestaurantFault.stale }
        let movement = StockMovement(establishmentID: shopID, itemID: itemID,
            delta: -line.quantity, reason: "Boisson servie", actorID: actor)
        movement.id = movementID
        db.insert(movement)
        drink.stockReserved -= line.quantity
        drink.stockOnHand -= line.quantity
        drink.updatedAt = .now
        return movementID
    }

    func finish(_ table: DiningTable, order: CommerceOrder, paid: Bool,
                tender: Tender? = nil, received: Int64? = nil, confirmed: Bool = false,
                expectedDue: Int64? = nil) throws {
        if paid {
            guard let tender else { throw RestaurantFault.invalid }
            try takePayment(table, order: order, tender: tender, received: received, confirmed: confirmed,
                partial: nil, expectedDue: expectedDue)
            return
        }
        try authorize()
        try check(table, order)
        guard !table.billRequested else { throw RestaurantFault.stale }
        table.billRequested = true
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.bill.requested", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: [table.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }

    func recordPartialPayment(_ table: DiningTable, order: CommerceOrder, tender: Tender,
                              amount: Int64, confirmed: Bool, expectedDue: Int64) throws {
        try takePayment(table, order: order, tender: tender, received: tender == .cash ? amount : nil,
            confirmed: confirmed, partial: amount, expectedDue: expectedDue)
    }

    func paymentBalance(_ table: DiningTable, order: CommerceOrder) throws -> Int64 {
        try authorize()
        try check(table, order)
        guard table.billRequested else { throw RestaurantFault.stale }
        let orderID = order.id
        let lines = try db.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate { $0.orderID == orderID }))
        let payments = try db.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.orderID == orderID }))
        return try RestaurantBill.checkoutBalance(order, lines: lines, payments: payments)
    }

    private func takePayment(_ table: DiningTable, order: CommerceOrder, tender: Tender,
                             received: Int64?, confirmed: Bool, partial: Int64?, expectedDue: Int64?) throws {
        let due = try paymentBalance(table, order: order)
        guard expectedDue == nil || expectedDue == due else { throw RestaurantFault.balanceChanged }
        let amount = partial ?? due
        guard amount > 0, partial == nil || amount < due,
              (tender == .cash ? (received ?? -1) >= amount : confirmed) else { throw RestaurantFault.invalid }

        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id, method: tender.rawValue,
                                    amountMinor: amount, confirmedByID: actor)
        payment.cashReceived = tender == .cash ? received : nil
        db.insert(payment)
        let paid = amount == due
        if paid {
            order.state = .completed
            order.restaurantKeepsTable = true
            table.billRequested = false
        }
        do {
            try BusinessOutbox.enqueue(kind: paid ? "restaurant.order.paid" : "restaurant.order.partially-paid",
                establishmentID: shop.id, entityID: order.id, actorID: actor,
                relatedIDs: [table.id, payment.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }
    func release(_ table: DiningTable, after order: CommerceOrder) throws {
        try authorize()
        guard table.establishmentID == shop.id, order.establishmentID == shop.id,
              order.tableID == table.id, order.state == .completed, order.restaurantKeepsTable == true,
              table.isOccupied, table.activeSessionID == order.id else { throw RestaurantFault.stale }
        table.lastReleasedSessionID = order.id
        table.activeSessionID = nil
        table.isOccupied = false
        table.billRequested = false
        do {
            try BusinessOutbox.enqueue(kind: "restaurant.table.released", establishmentID: shop.id,
                entityID: table.id, actorID: actor, relatedIDs: [order.id], in: db)
            try save()
        } catch { db.rollback(); throw error }
    }

}
