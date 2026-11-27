import Foundation
import SwiftData
import XCTest
@testable import COVI

// Modèles antérieurs au suivi du coût, de l’absence et de la famille boutique.
private enum LegacyNativeStore {
    @Model final class CatalogItem {
        @Attribute(.unique) var id: UUID
        var establishmentID: UUID
        var title: String
        var priceMinor: Int64
        var isService: Bool
        var salonPercent: Int = 0
        var salonDurationMinutes: Int?
        var salonDurationWasCleared: Bool?
        var menuCategory: String?
        var soldOut: Bool = false
        var stockOnHand: Int
        var stockReserved: Int
        var updatedAt: Date

        init(id: UUID = UUID(), establishmentID: UUID, title: String,
             priceMinor: Int64, isService: Bool = false) {
            self.id = id
            self.establishmentID = establishmentID
            self.title = title
            self.priceMinor = priceMinor
            self.isService = isService
            self.stockOnHand = 0
            self.stockReserved = 0
            self.updatedAt = .now
        }
    }

    @Model final class Bale {
        @Attribute(.unique) var id: UUID
        var shop: UUID
        var label: String
        var cost: Int64
        var received: Date

        init(id: UUID, shop: UUID, label: String, cost: Int64, received: Date) {
            self.id = id
            self.shop = shop
            self.label = label
            self.cost = cost
            self.received = received
        }
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

        init(id: UUID, shop: UUID, client: UUID, service: UUID, start: Date, end: Date) {
            self.id = id
            self.shop = shop
            self.client = client
            self.service = service
            stylist = "Chloé"
            self.start = start
            self.end = end
            walkIn = false
        }
    }
}

@MainActor
final class LotCostMigrationTests: XCTestCase {
    func testLegacySQLiteCostsStockAndSalonAppointmentsSurviveMigrationAndReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("covi.store")
        let owner = UUID()
        let shopID = UUID()
        let zeroID = UUID()
        let paidID = UUID()
        let itemID = UUID()
        let movementID = UUID()
        let received = Date(timeIntervalSince1970: 1_790_000_000)
        let salonID = UUID()
        let openVisitID = UUID()
        let paidVisitID = UUID()
        let retainedReceipt = UUID()
        let appointmentEnd = received.addingTimeInterval(1_800)
        let recordedAbsence = appointmentEnd.addingTimeInterval(60)

        try autoreleasepool {
            let schema = Schema([
                MaintenanceEntry.self,
                LegacyNativeStore.SalonVisit.self, SalonClient.self, SalonSaleLine.self, SalonStaff.self,
                LegacyNativeStore.Bale.self, SyncCheckpoint.self, CloudAccountBinding.self,
                ReceiptCloudCheckpoint.self, ReceiptCloudMarker.self,
                ExpenseCloudCheckpoint.self, ExpenseCloudMarker.self, PendingExpenseVoid.self,
                OperationalCloudCheckpoint.self, OperationalCloudMarker.self,
                Account.self, Establishment.self, Membership.self, ExpenseEntry.self,
                LegacyNativeStore.CatalogItem.self, DiningTable.self, CommerceOrder.self,
                Refund.self, OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self,
                RestaurantIncident.self
            ])
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let db = ModelContext(container)
            let shop = Establishment(id: shopID, ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
            db.insert(shop)
            db.insert(LegacyNativeStore.Bale(id: zeroID, shop: shopID, label: "Zéro confirmé", cost: 0, received: received))
            db.insert(LegacyNativeStore.Bale(id: paidID, shop: shopID, label: "Achat", cost: 12500, received: received))
            let article = LegacyNativeStore.CatalogItem(id: itemID, establishmentID: shopID,
                title: "Veste", priceMinor: 3000)
            article.stockOnHand = 2
            db.insert(article)
            let movement = StockMovement(establishmentID: shopID, itemID: itemID,
                delta: 2, reason: "Arrivage", actorID: owner)
            movement.id = movementID
            movement.baleID = paidID
            db.insert(movement)
            let salon = Establishment(id: salonID, ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
            let client = SalonClient(shop: salonID, name: "Mireille")
            let service = LegacyNativeStore.CatalogItem(establishmentID: salonID, title: "Coupe",
                priceMinor: 5_000, isService: true)
            db.insert(salon); db.insert(client); db.insert(service)
            let openVisit = LegacyNativeStore.SalonVisit(id: openVisitID, shop: salonID, client: client.id,
                service: service.id, start: received, end: appointmentEnd)
            let paidVisit = LegacyNativeStore.SalonVisit(id: paidVisitID, shop: salonID, client: client.id,
                service: service.id, start: received.addingTimeInterval(-1_800), end: received)
            paidVisit.receipt = retainedReceipt
            db.insert(openVisit); db.insert(paidVisit)
            try db.save()
        }

        // Point d'entrée réel de l'application, avec sa migration automatique.
        try autoreleasepool {
            let db = ModelContext(try PersistenceController.makeContainer(storeURL: url))
            let lots = try db.fetch(FetchDescriptor<COVI.Bale>())
            XCTAssertEqual(lots.count, 2)
            let zero = try XCTUnwrap(lots.first { $0.id == zeroID })
            let paid = try XCTUnwrap(lots.first { $0.id == paidID })
            XCTAssertEqual(zero.knownCost, 0)
            XCTAssertTrue(zero.costKnown)
            XCTAssertEqual(paid.knownCost, 12500)
            XCTAssertTrue(paid.costKnown)
            XCTAssertEqual(paid.shop, shopID)
            XCTAssertEqual(paid.received, received)
            let article = try XCTUnwrap(db.fetch(FetchDescriptor<CatalogItem>(
                predicate: #Predicate { $0.id == itemID })).first)
            XCTAssertEqual(article.id, itemID)
            XCTAssertEqual(article.stockOnHand, 2)
            XCTAssertEqual(article.boutiqueFamily, .uncategorized)
            article.boutiqueFamily = .jackets
            let movement = try XCTUnwrap(db.fetch(FetchDescriptor<StockMovement>()).first)
            XCTAssertEqual(movement.id, movementID)
            XCTAssertEqual(movement.baleID, paidID)
            XCTAssertEqual(movement.delta, 2)
            let visits = try db.fetch(FetchDescriptor<COVI.SalonVisit>())
            XCTAssertEqual(visits.count, 2)
            let openVisit = try XCTUnwrap(visits.first { $0.id == openVisitID })
            let paidVisit = try XCTUnwrap(visits.first { $0.id == paidVisitID })
            XCTAssertTrue(openVisit.isOpen)
            XCTAssertNil(openVisit.missedAt)
            XCTAssertNil(paidVisit.missedAt)
            XCTAssertEqual(paidVisit.receipt, retainedReceipt)
            try SalonLedger.markMissed(openVisit, shop: salonID, actor: owner, at: recordedAbsence, db: db)
            db.insert(COVI.Bale(shop: shopID, label: "Coût absent", cost: nil))
            try db.save()
        }

        let db = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let article = try XCTUnwrap(db.fetch(FetchDescriptor<CatalogItem>(
            predicate: #Predicate { $0.id == itemID })).first)
        XCTAssertEqual(article.boutiqueFamily, .jackets)
        XCTAssertEqual(article.stockOnHand, 2)
        let lots = try db.fetch(FetchDescriptor<COVI.Bale>())
        XCTAssertEqual(lots.count, 3)
        XCTAssertEqual(lots.first { $0.id == zeroID }?.knownCost, 0)
        XCTAssertEqual(lots.first { $0.id == paidID }?.knownCost, 12500)
        let unknown = try XCTUnwrap(lots.first { $0.label == "Coût absent" })
        XCTAssertNil(unknown.knownCost)
        XCTAssertFalse(unknown.costKnown)
        let visits = try db.fetch(FetchDescriptor<COVI.SalonVisit>())
        XCTAssertEqual(visits.first { $0.id == openVisitID }?.missedAt, recordedAbsence)
        XCTAssertEqual(visits.first { $0.id == paidVisitID }?.receipt, retainedReceipt)
    }
}
