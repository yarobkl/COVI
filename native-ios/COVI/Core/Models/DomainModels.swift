import Foundation
import SwiftData

enum BusinessKind: String, Codable, CaseIterable { case boutique, restaurant, salon }
enum StaffRole: String, Codable { case owner, manager, cashier, waiter, kitchen, stylist }
enum OrderState: String, Codable { case draft, pending, accepted, preparing, ready, served, completed, cancelled }
enum SyncState: String, Codable { case pending, syncing, synced, conflict, failed }

@Model final class Account {
    @Attribute(.unique) var id: UUID
    var fullName: String
    var email: String
    var phone: String
    init(id: UUID = UUID(), fullName: String, email: String, phone: String) {
        self.id = id; self.fullName = fullName; self.email = email; self.phone = phone
    }
}

@Model final class Establishment {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var name: String
    var kindRaw: String
    var city: String
    var currencyCode: String
    var archived: Bool
    var updatedAt: Date
    var kind: BusinessKind { get { BusinessKind(rawValue: kindRaw) ?? .boutique } set { kindRaw = newValue.rawValue } }
    init(id: UUID = UUID(), ownerID: UUID, name: String, kind: BusinessKind, city: String, currencyCode: String = "XAF") {
        self.id = id; self.ownerID = ownerID; self.name = name; self.kindRaw = kind.rawValue
        self.city = city; self.currencyCode = currencyCode; self.archived = false; self.updatedAt = .now
    }
}

@Model final class Membership {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var establishmentID: UUID
    var roleRaw: String
    var active: Bool
    var role: StaffRole { get { StaffRole(rawValue: roleRaw) ?? .cashier } set { roleRaw = newValue.rawValue } }
    init(accountID: UUID, establishmentID: UUID, role: StaffRole) {
        self.id = UUID(); self.accountID = accountID; self.establishmentID = establishmentID
        self.roleRaw = role.rawValue; self.active = true
    }
}

@Model final class CatalogItem {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var title: String
    var priceMinor: Int64
    var isService: Bool
    var salonPercent: Int = 0
    var menuCategory: String?
    var soldOut: Bool = false
    var stockOnHand: Int
    var stockReserved: Int
    var updatedAt: Date
    init(establishmentID: UUID, title: String, priceMinor: Int64, isService: Bool = false) {
        self.id = UUID(); self.establishmentID = establishmentID; self.title = title
        self.priceMinor = priceMinor; self.isService = isService
        self.stockOnHand = 0; self.stockReserved = 0; self.updatedAt = .now
    }
}

@Model final class DiningTable {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var label: String
    var capacity: Int
    var isOccupied: Bool
    var activeSessionID: UUID?
    var billRequested: Bool = false
    init(establishmentID: UUID, label: String, capacity: Int) {
        self.id = UUID(); self.establishmentID = establishmentID; self.label = label
        self.capacity = capacity; self.isOccupied = false
    }
}

@Model final class CommerceOrder {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var tableID: UUID?
    var customerID: UUID?
    var createdByID: UUID
    var stateRaw: String
    var createdAt: Date
    var totalMinor: Int64
    var discountMinor: Int64 = 0
    var state: OrderState { get { OrderState(rawValue: stateRaw) ?? .draft } set { stateRaw = newValue.rawValue } }
    init(establishmentID: UUID, createdByID: UUID, tableID: UUID? = nil) {
        self.id = UUID(); self.establishmentID = establishmentID; self.createdByID = createdByID
        self.tableID = tableID; self.customerID = nil; self.stateRaw = OrderState.draft.rawValue
        self.createdAt = .now; self.totalMinor = 0
    }
}

@Model final class OrderLine {
    @Attribute(.unique) var id: UUID
    var orderID: UUID
    var catalogItemID: UUID
    var quantity: Int
    var unitPriceMinor: Int64
    var dishName: String?
    var preparation: String?
    var sentAt: Date?
    init(orderID: UUID, catalogItemID: UUID, quantity: Int, unitPriceMinor: Int64) {
        self.id = UUID(); self.orderID = orderID; self.catalogItemID = catalogItemID
        self.quantity = quantity; self.unitPriceMinor = unitPriceMinor
    }
}

@Model final class PaymentRecord {
    @Attribute(.unique) var id: UUID
    var orderID: UUID
    var establishmentID: UUID
    var method: String
    var amountMinor: Int64
    var confirmedByID: UUID
    var confirmedAt: Date
    var cashReceived: Int64?
    init(orderID: UUID, establishmentID: UUID, method: String, amountMinor: Int64, confirmedByID: UUID) {
        self.id = UUID(); self.orderID = orderID; self.establishmentID = establishmentID
        self.method = method; self.amountMinor = amountMinor; self.confirmedByID = confirmedByID; self.confirmedAt = .now
    }
}

@Model final class StockMovement {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var itemID: UUID
    var delta: Int
    var baleID: UUID?
    var reason: String
    var actorID: UUID
    var createdAt: Date
    init(establishmentID: UUID, itemID: UUID, delta: Int, reason: String, actorID: UUID) {
        self.id = UUID(); self.establishmentID = establishmentID; self.itemID = itemID
        self.delta = delta; self.reason = reason; self.actorID = actorID; self.createdAt = .now
    }
}

@Model final class OutboxEvent {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var entityID: UUID
    var eventType: String
    var payloadJSON: Data
    var stateRaw: String
    var attempts: Int
    var createdAt: Date
    var state: SyncState { get { SyncState(rawValue: stateRaw) ?? .pending } set { stateRaw = newValue.rawValue } }
    init(establishmentID: UUID, entityID: UUID, eventType: String, payloadJSON: Data) {
        self.id = UUID(); self.establishmentID = establishmentID; self.entityID = entityID
        self.eventType = eventType; self.payloadJSON = payloadJSON; self.stateRaw = SyncState.pending.rawValue
        self.attempts = 0; self.createdAt = .now
    }
}
