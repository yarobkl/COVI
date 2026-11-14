import Foundation
import SwiftData

enum SalonTeam: String, CaseIterable { case chloe = "Chloé", brice = "Brice", sarah = "Sarah" }

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
    static func book(shop: UUID, client: SalonClient, item: CatalogItem, team: SalonTeam, start: Date,
                     minutes: Int, walkIn: Bool, db: ModelContext) throws {
        guard item.establishmentID == shop, item.isService, client.shop == shop, (5...720).contains(minutes) else { throw SalonFault.invalid }
        let end = start.addingTimeInterval(Double(minutes * 60))
        let person = team.rawValue, cid = client.id
        let matches = FetchDescriptor<SalonVisit>(predicate: #Predicate {
            $0.shop == shop && !$0.cancelled && ($0.stylist == person || $0.client == cid) && $0.start < end && $0.end > start
        })
        guard try db.fetchCount(matches) == 0 else { throw SalonFault.clash }
        db.insert(SalonVisit(shop: shop, client: cid, service: item.id, stylist: person, start: start, end: end, walkIn: walkIn))
        try save(db)
    }
    static func pay(shop: Establishment, actor: UUID, pin: PINManager, client: SalonClient, team: SalonTeam,
                    visit: SalonVisit?, basket: [UUID:Int], menu: [CatalogItem], tender: Tender, db: ModelContext) throws {
        guard !shop.archived, pin.isUnlocked, pin.unlockedStaffID == actor else { throw SalonFault.access }
        guard client.shop == shop.id, !basket.isEmpty else { throw SalonFault.invalid }
        if let visit {
            guard visit.shop == shop.id, visit.receipt == nil, !visit.cancelled, visit.client == client.id,
                  visit.stylist == team.rawValue, basket[visit.service] == 1 else { throw SalonFault.stale }
        }
        let order = CommerceOrder(establishmentID: shop.id, createdByID: actor)
        var validated: [(CatalogItem, Int, Int64)] = []
        for (id, qty) in basket {
            guard let item = menu.first(where: { $0.id == id && $0.establishmentID == shop.id }),
                  qty > 0, item.priceMinor > 0, (0...100).contains(item.salonPercent) else { throw SalonFault.invalid }
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
            db.insert(OrderLine(orderID: order.id, catalogItemID: item.id, quantity: qty, unitPriceMinor: item.priceMinor))
            db.insert(SalonSaleLine(order: order, client: client.id, stylist: team.rawValue, item: item, units: qty, gross: gross))
            if !item.isService {
                item.stockOnHand -= qty; item.updatedAt = .now
                db.insert(StockMovement(establishmentID: shop.id, itemID: item.id, delta: -qty, reason: "Vente salon · " + order.id.uuidString, actorID: actor))
            }
        }
        db.insert(PaymentRecord(orderID: order.id, establishmentID: shop.id, method: tender.rawValue, amountMinor: order.totalMinor, confirmedByID: actor))
        visit?.receipt = order.id
        try save(db); pin.touch()
    }
}
