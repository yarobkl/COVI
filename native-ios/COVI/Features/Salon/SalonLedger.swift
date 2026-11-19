import Foundation
import SwiftData

@Model final class SalonStaff {
    @Attribute(.unique) var id: UUID
    var shop: UUID
    var name: String
    var active: Bool
    init(shop: UUID, name: String) {
        id = UUID(); self.shop = shop
        self.name = name; active = true
    }
}

@Model final class SalonClient {
    @Attribute(.unique) var id: UUID
    var shop: UUID
    var name: String
    var phone = ""
    var notes = ""
    var preferences = ""
    init(shop: UUID, name: String) { id = UUID(); self.shop = shop; self.name = name }
}

@Model final class SalonVisit {
    @Attribute(.unique) var id: UUID
    var shop: UUID
    var client: UUID
    var service: UUID
    var stylist: String
    var start: Date
    var end: Date
    var walkIn: Bool
    var cancelled = false
    var receipt: UUID?
    init(shop: UUID, client: UUID, service: UUID, stylist: String, start: Date, end: Date, walkIn: Bool) {
        id = UUID(); self.shop = shop; self.client = client; self.service = service
        self.stylist = stylist; self.start = start; self.end = end; self.walkIn = walkIn
    }
}

@Model final class SalonSaleLine {
    @Attribute(.unique) var id: UUID
    var shop: UUID
    var order: UUID
    var client: UUID
    var stylist: String
    var title: String
    var service: Bool
    var units: Int
    var gross: Int64
    var percent: Int
    var commission: Int64
    var date: Date
    init(order: CommerceOrder, client: UUID, stylist: String, item: CatalogItem, units: Int, gross: Int64) {
        id = UUID(); shop = order.establishmentID; self.order = order.id; self.client = client
        self.stylist = stylist; title = item.title; service = item.isService; self.units = units
        self.gross = gross; percent = item.salonPercent; date = order.createdAt
        let rate = Int64(item.salonPercent)
        commission = (gross / 100) * rate + ((gross % 100) * rate) / 100
    }
}

enum SalonFault: String, LocalizedError {
    case clash = "Ce collaborateur ou ce client a déjà un rendez-vous sur ce créneau."
    case invalid = "Vérifiez la sélection, le prix et les quantités."
    case stock = "Stock disponible insuffisant."
    case access = "Déverrouillez la caisse avec votre PIN."
    case stale = "Ce rendez-vous a été annulé ou déjà encaissé."
    var errorDescription: String? { rawValue }
}

@MainActor enum SalonLedger {
    static func save(_ db: ModelContext) throws {
        do { try db.save() } catch { db.rollback(); throw error }
    }
    static func updateClient(_ client: SalonClient, shop: UUID, actor: UUID,
                             name: String, phone: String, notes: String, preferences: String,
                             db: ModelContext) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard client.shop == shop, (2...120).contains(cleaned.count), number.count <= 30,
              notes.count <= 2_000, preferences.count <= 1_000 else { throw SalonFault.invalid }
        client.name = cleaned
        client.phone = number
        client.notes = notes
        client.preferences = preferences
        do {
            try BusinessOutbox.enqueue(kind: "salon.client.updated", establishmentID: shop,
                entityID: client.id, actorID: actor, in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }

    private static func catalogTitle(_ title: String, shop: UUID, excluding: UUID?,
                                     db: ModelContext) throws -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(cleaned.count) else { throw SalonFault.invalid }
        let candidates = try db.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == shop
        }))
        guard !candidates.contains(where: {
            $0.id != excluding && $0.title.compare(cleaned,
                options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw SalonFault.invalid }
        return cleaned
    }

    @discardableResult
    static func createCatalog(shop: Establishment, actor: UUID, title: String,
                              price: Int64, service: Bool, quantity: Int, percent: Int,
                              db: ModelContext) throws -> CatalogItem {
        guard shop.kind == .salon, !shop.archived, price > 0, (0...100).contains(percent),
              quantity >= 0, (!service || quantity == 0) else { throw SalonFault.invalid }
        let name = try catalogTitle(title, shop: shop.id, excluding: nil, db: db)
        let item = CatalogItem(establishmentID: shop.id, title: name,
                               priceMinor: price, isService: service)
        item.salonPercent = percent
        item.stockOnHand = quantity
        db.insert(item)
        var movementIDs: [UUID] = []
        if quantity > 0 {
            let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
                delta: quantity, reason: "Stock initial du salon", actorID: actor)
            db.insert(movement)
            movementIDs.append(movement.id)
        }
        do {
            try BusinessOutbox.enqueue(kind: service ? "salon.service.created" : "salon.product.created",
                establishmentID: shop.id, entityID: item.id, actorID: actor,
                relatedIDs: movementIDs, in: db)
            try save(db)
            return item
        } catch { db.rollback(); throw error }
    }

    static func editCatalog(_ item: CatalogItem, shop: Establishment, actor: UUID,
                            title: String, price: Int64, percent: Int, db: ModelContext) throws {
        guard shop.kind == .salon, !shop.archived, item.establishmentID == shop.id,
              price > 0, (0...100).contains(percent) else { throw SalonFault.invalid }
        let name = try catalogTitle(title, shop: shop.id, excluding: item.id, db: db)
        guard name != item.title || price != item.priceMinor || percent != item.salonPercent else { return }
        item.title = name; item.priceMinor = price; item.salonPercent = percent
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: "salon.catalog.edited", establishmentID: shop.id,
                entityID: item.id, actorID: actor, in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }

    static func setCatalogAvailability(_ item: CatalogItem, shop: Establishment,
                                       actor: UUID, available: Bool, db: ModelContext) throws {
        guard shop.kind == .salon, !shop.archived, item.establishmentID == shop.id else {
            throw SalonFault.invalid
        }
        guard item.soldOut == available else { return }
        item.soldOut = !available; item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: available ? "salon.catalog.reactivated" : "salon.catalog.suspended",
                establishmentID: shop.id, entityID: item.id, actorID: actor, in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }

    static func adjustProductStock(_ item: CatalogItem, shop: Establishment,
                                   actor: UUID, counted: Int, reason: String, db: ModelContext) throws {
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shop.kind == .salon, !shop.archived, item.establishmentID == shop.id,
              !item.isService, counted >= item.stockReserved, counted >= 0,
              item.stockOnHand >= 0, (3...200).contains(why.count) else { throw SalonFault.invalid }
        let (delta, overflow) = counted.subtractingReportingOverflow(item.stockOnHand)
        guard !overflow, delta != 0 else { throw SalonFault.invalid }
        let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
                                     delta: delta, reason: "Inventaire salon · " + why, actorID: actor)
        db.insert(movement)
        item.stockOnHand = counted; item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: "salon.stock.adjusted", establishmentID: shop.id,
                entityID: item.id, actorID: actor, relatedIDs: [movement.id], in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }
    static func book(shop: UUID, actor: UUID, client: SalonClient, item: CatalogItem, team: SalonStaff, start: Date,
                     minutes: Int, walkIn: Bool, db: ModelContext) throws {
        guard item.establishmentID == shop, item.isService, !item.soldOut, client.shop == shop,
              team.shop == shop, team.active, !team.name.isEmpty,
              (5...720).contains(minutes),
              start >= Date.now.addingTimeInterval(-60),
              start <= Date.now.addingTimeInterval(366 * 24 * 3_600) else {
            throw SalonFault.invalid
        }
        let end = start.addingTimeInterval(Double(minutes * 60))
        let person = team.name, cid = client.id
        let matches = FetchDescriptor<SalonVisit>(predicate: #Predicate {
            $0.shop == shop && !$0.cancelled && ($0.stylist == person || $0.client == cid) && $0.start < end && $0.end > start
        })
        guard try db.fetchCount(matches) == 0 else { throw SalonFault.clash }
        let visit = SalonVisit(shop: shop, client: cid, service: item.id,
                               stylist: person, start: start, end: end, walkIn: walkIn)
        db.insert(visit)
        do {
            try BusinessOutbox.enqueue(kind: "salon.appointment.created",
                establishmentID: shop, entityID: visit.id, actorID: actor,
                relatedIDs: [client.id, item.id, team.id], in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }

    static func cancel(shop: UUID, actor: UUID, visit: SalonVisit, db: ModelContext) throws {
        guard visit.shop == shop, !visit.cancelled, visit.receipt == nil else { throw SalonFault.stale }
        visit.cancelled = true
        do {
            try BusinessOutbox.enqueue(kind: "salon.appointment.cancelled", establishmentID: shop,
                entityID: visit.id, actorID: actor, in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }

    static func reschedule(_ visit: SalonVisit, shop: UUID, actor: UUID,
                           client: SalonClient, item: CatalogItem, team: SalonStaff,
                           start: Date, minutes: Int, db: ModelContext) throws {
        guard visit.shop == shop, !visit.cancelled, visit.receipt == nil else { throw SalonFault.stale }
        guard client.shop == shop, item.establishmentID == shop, item.isService, !item.soldOut,
              team.shop == shop, team.active, !team.name.isEmpty,
              (5...720).contains(minutes), start >= Date.now.addingTimeInterval(-60),
              start <= Date.now.addingTimeInterval(366 * 24 * 3_600)
        else { throw SalonFault.invalid }
        let end = start.addingTimeInterval(Double(minutes * 60))
        let visitID = visit.id, person = team.name, clientID = client.id
        let competing = FetchDescriptor<SalonVisit>(predicate: #Predicate {
            $0.shop == shop && $0.id != visitID && !$0.cancelled &&
            ($0.stylist == person || $0.client == clientID) && $0.start < end && $0.end > start
        })
        guard try db.fetchCount(competing) == 0 else { throw SalonFault.clash }
        visit.client = client.id
        visit.service = item.id
        visit.stylist = team.name
        visit.start = start
        visit.end = end
        visit.walkIn = false
        do {
            try BusinessOutbox.enqueue(kind: "salon.appointment.rescheduled",
                establishmentID: shop, entityID: visit.id, actorID: actor,
                relatedIDs: [client.id, item.id, team.id], in: db)
            try save(db)
        } catch { db.rollback(); throw error }
    }
    @discardableResult static func pay(shop: Establishment, actor: UUID, pin: PINManager, client: SalonClient, team: String,
                    visit: SalonVisit?, basket: [UUID:Int], menu: [CatalogItem],
                    tender: Tender, confirmed: Bool, db: ModelContext) throws -> CommerceOrder {
        guard !shop.archived, pin.mayOperate(shop: shop, actor: actor) else { throw SalonFault.access }
        guard confirmed, client.shop == shop.id, !basket.isEmpty, !team.isEmpty else { throw SalonFault.invalid }
        let shopID = shop.id, person = team
        let workers = try db.fetch(FetchDescriptor<SalonStaff>(predicate: #Predicate {
            $0.shop == shopID && $0.name == person
        }))
        guard workers.count == 1, workers[0].active || visit != nil else { throw SalonFault.invalid }
        if let visit {
            guard visit.shop == shop.id, visit.receipt == nil, !visit.cancelled, visit.client == client.id,
                  visit.stylist == team, basket[visit.service] == 1 else { throw SalonFault.stale }
        }
        let order = CommerceOrder(establishmentID: shop.id, createdByID: actor)
        var validated: [(CatalogItem, Int, Int64)] = []
        for (id, qty) in basket {
            guard let item = menu.first(where: { $0.id == id && $0.establishmentID == shop.id }),
                  qty > 0, item.priceMinor > 0, (0...100).contains(item.salonPercent) else { throw SalonFault.invalid }
            guard !item.soldOut || (item.isService && visit?.service == item.id) else {
                throw SalonFault.invalid
            }
            if !item.isService {
                guard item.stockReserved >= 0, item.stockOnHand >= item.stockReserved,
                      qty <= item.stockOnHand - item.stockReserved else { throw SalonFault.stock }
            }
            let (gross, overflow) = item.priceMinor.multipliedReportingOverflow(by: Int64(qty))
            let (total, exceeds) = order.totalMinor.addingReportingOverflow(gross)
            guard !overflow, !exceeds else { throw SalonFault.invalid }
            order.totalMinor = total
            validated.append((item, qty, gross))
        }
        order.state = .completed; order.customerID = client.id; db.insert(order)
        for (item, qty, gross) in validated {
            let detail = OrderLine(orderID: order.id, catalogItemID: item.id, quantity: qty,
                                   unitPriceMinor: item.priceMinor)
            detail.dishName = item.title
            db.insert(detail)
            db.insert(SalonSaleLine(order: order, client: client.id, stylist: team, item: item, units: qty, gross: gross))
            if !item.isService {
                item.stockOnHand -= qty; item.updatedAt = .now
                db.insert(StockMovement(establishmentID: shop.id, itemID: item.id, delta: -qty, reason: "Vente salon · " + order.id.uuidString, actorID: actor))
            }
        }
        db.insert(PaymentRecord(orderID: order.id, establishmentID: shop.id, method: tender.rawValue, amountMinor: order.totalMinor, confirmedByID: actor))
        visit?.receipt = order.id
        do {
            try BusinessOutbox.enqueue(kind: "salon.sale.completed", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: visit.map { [$0.id] } ?? [], in: db)
            try save(db)
            pin.touch()
            return order
        } catch { db.rollback(); throw error }
    }
}
