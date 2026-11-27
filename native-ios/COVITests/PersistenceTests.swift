import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class PersistenceTests: XCTestCase {
    func testAddingRestaurantIncidentsPreservesAnExistingServedOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("covi.store")
        let owner = UUID()
        let lineID: UUID
        let pin = PINManager(keychain: InMemorySecureStore())

        do {
            // Schéma du commit précédant l’ajout de RestaurantIncident.
            let legacy = Schema([
                MaintenanceEntry.self,
                SalonVisit.self, SalonClient.self, SalonSaleLine.self, SalonStaff.self,
                Bale.self, SyncCheckpoint.self, CloudAccountBinding.self,
                ReceiptCloudCheckpoint.self, ReceiptCloudMarker.self,
                ExpenseCloudCheckpoint.self, ExpenseCloudMarker.self, PendingExpenseVoid.self,
                OperationalCloudCheckpoint.self, OperationalCloudMarker.self,
                Account.self, Establishment.self, Membership.self, ExpenseEntry.self,
                CatalogItem.self, DiningTable.self, CommerceOrder.self,
                Refund.self, OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self
            ])
            let configuration = ModelConfiguration(schema: legacy, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: legacy, configurations: [configuration])
            let context = ModelContext(container)
            let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
            let table = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
            let dish = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 8_000)
            dish.menuCategory = MenuGroup.food.rawValue
            context.insert(shop); context.insert(table); context.insert(dish)
            try context.save()
            let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: pin, db: context)
            try service.open(table)
            let order = try XCTUnwrap(context.fetch(FetchDescriptor<CommerceOrder>()).first)
            try service.send([dish.id: 1], menu: [dish], table: table, order: order)
            let line = try XCTUnwrap(context.fetch(FetchDescriptor<OrderLine>()).first)
            try service.advance(line, from: .received, table: table, order: order)
            try service.advance(line, from: .cooking, table: table, order: order)
            try service.advance(line, from: .ready, table: table, order: order)
            lineID = line.id
        }

        do {
            let context = ModelContext(try PersistenceController.makeContainer(storeURL: storeURL))
            let shop = try XCTUnwrap(context.fetch(FetchDescriptor<Establishment>()).first)
            let table = try XCTUnwrap(context.fetch(FetchDescriptor<DiningTable>()).first)
            let order = try XCTUnwrap(context.fetch(FetchDescriptor<CommerceOrder>()).first)
            XCTAssertEqual(table.activeSessionID, order.id)
            XCTAssertEqual(order.totalMinor, 8_000)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<RestaurantIncident>()), 0)
            let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: pin, db: context)
            try service.recordIncident(lineID: lineID, table: table, order: order, reason: "Plat servi froid")
        }

        let context = ModelContext(try PersistenceController.makeContainer(storeURL: storeURL))
        let incident = try XCTUnwrap(context.fetch(FetchDescriptor<RestaurantIncident>()).first)
        XCTAssertEqual(incident.lineID, lineID)
        XCTAssertEqual(incident.reason, "Plat servi froid")
    }

    func testReopeningStorePreservesStockAndMovementIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("covi.store")

        let ownerID = UUID()
        let shopID: UUID
        let itemID: UUID
        do {
            let container = try PersistenceController.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let shop = Establishment(ownerID: ownerID, name: "Boutique", kind: .boutique, city: "Brazzaville")
            let item = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_500)
            item.stockOnHand = 3
            shopID = shop.id
            itemID = item.id
            context.insert(shop)
            context.insert(item)
            context.insert(StockMovement(establishmentID: shopID, itemID: itemID,
                delta: 3, reason: "Arrivage", actorID: ownerID))
            try context.save()
        }

        let container = try PersistenceController.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        let shop = try XCTUnwrap(context.fetch(FetchDescriptor<Establishment>()).first)
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogItem>()).first)
        let movement = try XCTUnwrap(context.fetch(FetchDescriptor<StockMovement>()).first)
        XCTAssertEqual(shop.id, shopID)
        XCTAssertEqual(shop.ownerID, ownerID)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.stockOnHand, 3)
        XCTAssertEqual(movement.itemID, itemID)
        try CloudOperationalSync.validateStock(shop: shop, context: context)
    }
}
