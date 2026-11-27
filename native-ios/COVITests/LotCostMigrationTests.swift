import Foundation
import SwiftData
import XCTest
@testable import COVI

// Modèle Bale antérieur à l'ajout de costKnown, avec les mêmes noms et types persistés.
private enum LegacyLotCost {
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
}

@MainActor
final class LotCostMigrationTests: XCTestCase {
    func testLegacySQLiteCostsAndLinkedStockSurviveMigrationAndReopening() throws {
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

        try autoreleasepool {
            let schema = Schema([
                MaintenanceEntry.self,
                SalonVisit.self, SalonClient.self, SalonSaleLine.self, SalonStaff.self,
                LegacyLotCost.Bale.self, SyncCheckpoint.self, CloudAccountBinding.self,
                ReceiptCloudCheckpoint.self, ReceiptCloudMarker.self,
                ExpenseCloudCheckpoint.self, ExpenseCloudMarker.self, PendingExpenseVoid.self,
                OperationalCloudCheckpoint.self, OperationalCloudMarker.self,
                Account.self, Establishment.self, Membership.self, ExpenseEntry.self,
                CatalogItem.self, DiningTable.self, CommerceOrder.self,
                Refund.self, OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self,
                RestaurantIncident.self
            ])
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let db = ModelContext(container)
            let shop = Establishment(id: shopID, ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
            db.insert(shop)
            db.insert(LegacyLotCost.Bale(id: zeroID, shop: shopID, label: "Zéro confirmé", cost: 0, received: received))
            db.insert(LegacyLotCost.Bale(id: paidID, shop: shopID, label: "Achat", cost: 12500, received: received))
            let article = CatalogItem(establishmentID: shopID, title: "Veste", priceMinor: 3000)
            article.id = itemID
            article.stockOnHand = 2
            db.insert(article)
            let movement = StockMovement(establishmentID: shopID, itemID: itemID,
                delta: 2, reason: "Arrivage", actorID: owner)
            movement.id = movementID
            movement.baleID = paidID
            db.insert(movement)
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
            let article = try XCTUnwrap(db.fetch(FetchDescriptor<CatalogItem>()).first)
            XCTAssertEqual(article.id, itemID)
            XCTAssertEqual(article.stockOnHand, 2)
            let movement = try XCTUnwrap(db.fetch(FetchDescriptor<StockMovement>()).first)
            XCTAssertEqual(movement.id, movementID)
            XCTAssertEqual(movement.baleID, paidID)
            XCTAssertEqual(movement.delta, 2)
            db.insert(COVI.Bale(shop: shopID, label: "Coût absent", cost: nil))
            try db.save()
        }

        let db = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let lots = try db.fetch(FetchDescriptor<COVI.Bale>())
        XCTAssertEqual(lots.count, 3)
        XCTAssertEqual(lots.first { $0.id == zeroID }?.knownCost, 0)
        XCTAssertEqual(lots.first { $0.id == paidID }?.knownCost, 12500)
        let unknown = try XCTUnwrap(lots.first { $0.label == "Coût absent" })
        XCTAssertNil(unknown.knownCost)
        XCTAssertFalse(unknown.costKnown)
    }
}
