import Foundation
import CoreGraphics
import XCTest
import SwiftData
@testable import COVI

@MainActor
final class BoutiquePhotoTests: XCTestCase {
    func testConservativePhotoSuggestions() {
        XCTAssertEqual(BoutiquePhotoProcessor.suggestedName(identifier: "shirt", confidence: 0.9), "Chemise")
        XCTAssertNil(BoutiquePhotoProcessor.suggestedName(identifier: "shirt", confidence: 0.2))
        XCTAssertNil(BoutiquePhotoProcessor.suggestedName(identifier: "unknown brand", confidence: 0.99))
        XCTAssertEqual(BoutiquePhotoProcessor.colorName(red: 0.04, green: 0.06, blue: 0.1), "Noir")
        XCTAssertEqual(BoutiquePhotoProcessor.colorName(red: 0.1, green: 0.3, blue: 0.8), "Bleu")
        XCTAssertThrowsError(try BoutiquePhotoProcessor.process(Data([0, 1, 2])))
    }

    func testStudioCentersSubjectAndPreservesProportions() {
        let canvas = CGSize(width: 400, height: 600)
        XCTAssertEqual(
            BoutiquePhotoProcessor.studioFrame(subject: CGSize(width: 400, height: 200), canvas: canvas),
            CGRect(x: 20, y: 210, width: 360, height: 180)
        )
        XCTAssertEqual(
            BoutiquePhotoProcessor.studioFrame(subject: CGSize(width: 100, height: 200), canvas: canvas),
            CGRect(x: 150, y: 200, width: 100, height: 200)
        )
    }

    func testPhotoSearchRejectsUnreadableInput() {
        XCTAssertThrowsError(try BoutiquePhotoSearch.matches(
            photo: Data([0, 1, 2]), shopID: UUID(), itemIDs: [UUID()]
        )) { error in
            XCTAssertEqual(error.localizedDescription, BoutiquePhotoFault.unreadable.localizedDescription)
        }
    }

    func testPhotoStorageKeepsOriginalAndIsolatesShops() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shop = UUID(), other = UUID(), article = UUID()
        let draft = BoutiquePhotoDraft(original: Data([1, 2, 3]), preview: Data([4, 5]),
            studio: Data([6, 7]), suggestion: nil, color: nil)
        try BoutiquePhotoStore.save(draft, description: "Test", shopID: shop, itemID: article, root: root)
        let directory = try BoutiquePhotoStore.directory(shopID: shop, itemID: article, root: root)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("original")), draft.original)
        XCTAssertEqual(BoutiquePhotoStore.data(shopID: shop, itemID: article, root: root), draft.preview)
        XCTAssertEqual(BoutiquePhotoStore.data(shopID: shop, itemID: article, studio: true, root: root), draft.studio)
        XCTAssertNil(BoutiquePhotoStore.data(shopID: other, itemID: article, root: root))
        XCTAssertThrowsError(try BoutiquePhotoStore.save(draft, description: "", shopID: shop, itemID: article, root: root))
        try BoutiquePhotoStore.remove(shopID: shop, itemID: article, root: root)
        XCTAssertNil(BoutiquePhotoStore.data(shopID: shop, itemID: article, root: root))
    }

    func testArrivalAccessIsCheckedAfterRoleChanges() throws {
        let schema = Schema([Establishment.self, Membership.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let db = ModelContext(container)
        let manager = UUID()
        let shop = Establishment(ownerID: UUID(), name: "Boutique", kind: .boutique, city: "Brazzaville")
        let membership = Membership(accountID: manager, establishmentID: shop.id, role: .manager)
        db.insert(shop)
        db.insert(membership)
        try db.save()
        XCTAssertNoThrow(try BoutiqueInventoryService.checkReceive(shop: shop, actor: manager, context: db))
        membership.active = false
        try db.save()
        XCTAssertThrowsError(try BoutiqueInventoryService.checkReceive(shop: shop, actor: manager, context: db))
        membership.active = true
        membership.roleRaw = StaffRole.cashier.rawValue
        try db.save()
        XCTAssertThrowsError(try BoutiqueInventoryService.checkReceive(shop: shop, actor: manager, context: db))
        shop.archived = true
        try db.save()
        XCTAssertThrowsError(try BoutiqueInventoryService.checkReceive(shop: shop, actor: shop.ownerID, context: db))
    }

    func testArrivalConfirmationDoesNotCreateStockTwice() throws {
        let schema = Schema([Establishment.self, Membership.self, CatalogItem.self, StockMovement.self, OutboxEvent.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let db = ModelContext(container)
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        db.insert(shop)
        try db.save()
        let id = UUID()
        defer { try? BoutiquePhotoStore.remove(shopID: shop.id, itemID: id) }
        let photo = BoutiquePhotoDraft(original: Data([1]), preview: Data([2]),
            studio: nil, suggestion: nil, color: nil)
        for _ in 0..<2 {
            let article = try BoutiqueInventoryService.create(shop: shop, name: "Veste", price: 500,
                actor: owner, context: db, initialStock: 1, photo: photo, arrivalID: id)
            XCTAssertEqual(article.id, id)
            XCTAssertEqual(article.stockOnHand, 1)
        }
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CatalogItem>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<StockMovement>()), 1)
    }

    func testInitialStockAndPermission() throws {
        let schema = Schema([Establishment.self, Membership.self, CatalogItem.self, StockMovement.self, OutboxEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let db = ModelContext(container)
        let owner = UUID(), cashier = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        db.insert(shop); db.insert(Membership(accountID: cashier, establishmentID: shop.id, role: .cashier))
        try db.save()
        XCTAssertThrowsError(try BoutiqueInventoryService.create(shop: shop, name: "Veste", price: 500,
            actor: cashier, context: db, initialStock: 1))
        XCTAssertThrowsError(try BoutiqueInventoryService.create(shop: shop, name: "Veste", price: 0,
            actor: owner, context: db, initialStock: 1))
        let product = try BoutiqueInventoryService.create(shop: shop, name: "Veste", price: 500,
            actor: owner, context: db, initialStock: 3)
        XCTAssertEqual(product.stockOnHand, 3)
        XCTAssertEqual(try db.fetch(FetchDescriptor<StockMovement>()).first?.delta, 3)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CatalogItem>()), 1)
    }
}
