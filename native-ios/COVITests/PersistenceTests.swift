import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class PersistenceTests: XCTestCase {
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
