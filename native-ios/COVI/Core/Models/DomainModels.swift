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

enum EstablishmentPolicy {
    static let maximumActivePerOwner = 3

    static func canCreate(owner: UUID, in shops: [Establishment]) -> Bool {
        shops.filter { $0.ownerID == owner && !$0.archived }.count < maximumActivePerOwner
    }
}

/// Ces devises sont saisies en unités entières dans COVI ; aucune conversion automatique.
enum SupportedCurrency {
    struct Option: Identifiable, Sendable {
        let code: String
        let label: String
        var id: String { code }
    }
    static let options: [Option] = [
        Option(code: "XAF", label: "Franc CFA · Afrique centrale"),
        Option(code: "XOF", label: "Franc CFA · Afrique de l'Ouest"),
        Option(code: "CDF", label: "Franc congolais · RDC"),
        Option(code: "RWF", label: "Franc rwandais"),
        Option(code: "BIF", label: "Franc burundais")
    ]
    static func allows(_ code: String) -> Bool { options.contains { $0.code == code } }

    @MainActor static func mayChange(_ shop: Establishment, to code: String,
                                     db: ModelContext) throws -> Bool {
        guard !shop.archived, allows(code), code != shop.currencyCode else { return false }
        let id = shop.id
        let orders = FetchDescriptor<CommerceOrder>(predicate: #Predicate { $0.establishmentID == id })
        let items = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.establishmentID == id })
        let expenses = FetchDescriptor<ExpenseEntry>(predicate: #Predicate { $0.establishmentID == id })
        let bales = FetchDescriptor<Bale>(predicate: #Predicate { $0.shop == id })
        return try db.fetchCount(orders) == 0 && db.fetchCount(items) == 0 &&
                   db.fetchCount(expenses) == 0 && db.fetchCount(bales) == 0
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

@MainActor enum StaffAccess {
    static func role(for actor: UUID, in shop: Establishment, memberships: [Membership]) -> StaffRole? {
        guard !shop.archived else { return nil }
        if actor == shop.ownerID { return .owner }
        let matches = memberships.filter { $0.accountID == actor && $0.establishmentID == shop.id }
        guard matches.count == 1, let membership = matches.first, membership.active,
              let role = StaffRole(rawValue: membership.roleRaw), role != .owner else { return nil }
        return role
    }

    static func role(for actor: UUID, in shop: Establishment, context: ModelContext) throws -> StaffRole? {
        if shop.archived || actor == shop.ownerID {
            return role(for: actor, in: shop, memberships: [])
        }
        let shopID = shop.id
        let memberships = try context.fetch(FetchDescriptor<Membership>(predicate: #Predicate {
            $0.accountID == actor && $0.establishmentID == shopID
        }))
        return role(for: actor, in: shop, memberships: memberships)
    }

    static func mayTakePayment(actor: UUID, in shop: Establishment, context: ModelContext) throws -> Bool {
        let currentRole = try role(for: actor, in: shop, context: context)
        return currentRole == .owner || currentRole == .manager || currentRole == .cashier
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
    var lastReleasedSessionID: UUID?
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
    var restaurantGuestCount: Int?
    var restaurantKeepsTable: Bool?
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

@Model final class ExpenseEntry {
    @Attribute(.unique) var id: UUID
    var establishmentID: UUID
    var actorID: UUID
    var category: String
    var amountMinor: Int64
    var spentAt: Date
    var note: String
    var voidedAt: Date?
    var voidedByID: UUID?
    init(establishmentID: UUID, actorID: UUID, category: String,
         amountMinor: Int64, spentAt: Date, note: String) {
        id = UUID(); self.establishmentID = establishmentID; self.actorID = actorID
        self.category = category; self.amountMinor = amountMinor
        self.spentAt = spentAt; self.note = note
    }
}

enum ExpenseCategory {
    static let all = ["Loyer", "Électricité", "Eau", "Internet", "Téléphone", "Salaire",
                      "Prime", "Transport", "Livraison", "Carburant", "Manutention",
                      "Emballage", "Sacs", "Cintres", "Nettoyage", "Réparations",
                      "Fournitures", "Publicité", "Influenceurs", "Frais bancaires",
                      "Frais Mobile Money", "Taxes", "Autre"]
}

@MainActor enum ExpenseLedger {
    enum Fault: LocalizedError {
        case invalid, unauthorized, ownerOnly, alreadyVoided
        var errorDescription: String? {
            switch self {
            case .invalid: "Vérifiez la catégorie, la date et le montant de la dépense."
            case .unauthorized: "Cette opération nécessite les droits du propriétaire ou du responsable."
            case .ownerOnly: "Seul le propriétaire peut annuler cette dépense."
            case .alreadyVoided: "Cette dépense a déjà été annulée."
            }
        }
    }

    @discardableResult
    static func record(shop: Establishment, actor: UUID, category: String,
                       amount: Int64, date: Date, note: String,
                       context: ModelContext) throws -> ExpenseEntry {
        if actor != shop.ownerID {
            guard try StaffAccess.role(for: actor, in: shop, context: context) == .manager else {
                throw Fault.unauthorized
            }
        }
        guard !shop.archived, ExpenseCategory.all.contains(category), amount > 0,
              date <= Date.now.addingTimeInterval(24 * 3_600),
              date >= Date.now.addingTimeInterval(-10 * 366 * 24 * 3_600) else { throw Fault.invalid }
        let entry = ExpenseEntry(establishmentID: shop.id, actorID: actor,
                                 category: category, amountMinor: amount, spentAt: date,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(entry)
        do {
            try BusinessOutbox.enqueue(kind: "expense.recorded", establishmentID: shop.id,
                entityID: entry.id, actorID: actor, in: context)
            try context.save()
            return entry
        } catch { context.rollback(); throw error }
    }

    static func void(_ expense: ExpenseEntry, shop: Establishment,
                     actor: UUID, context: ModelContext) throws {
        guard actor == shop.ownerID else { throw Fault.ownerOnly }
        guard expense.establishmentID == shop.id, !shop.archived else { throw Fault.invalid }
        guard expense.voidedAt == nil else { throw Fault.alreadyVoided }
        expense.voidedAt = .now
        expense.voidedByID = actor
        do {
            try BusinessOutbox.enqueue(kind: "expense.voided", establishmentID: shop.id,
                entityID: expense.id, actorID: actor, in: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

/// Stable, versioned business event. The same ModelContext save persists both the
/// domain mutation and its outbox entry; delivery happens separately.
struct BusinessEventPayload: Codable {
    let version: Int
    let kind: String
    let establishmentID: UUID
    let entityID: UUID
    let actorID: UUID
    let relatedIDs: [UUID]
    let occurredAt: Date
}

@MainActor enum BusinessOutbox {
    static func enqueue(kind: String, establishmentID: UUID, entityID: UUID,
                        actorID: UUID, relatedIDs: [UUID] = [], in context: ModelContext) throws {
        let payload = BusinessEventPayload(version: 1, kind: kind,
            establishmentID: establishmentID, entityID: entityID,
            actorID: actorID, relatedIDs: relatedIDs, occurredAt: .now)
        context.insert(OutboxEvent(establishmentID: establishmentID, entityID: entityID,
            eventType: "business.v1", payloadJSON: try JSONEncoder().encode(payload)))
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
