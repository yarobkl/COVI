import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CloudReceiptArchiveTests: XCTestCase {
    private func memory() throws -> ModelContext {
        let schema = Schema([CommerceOrder.self, OrderLine.self, PaymentRecord.self,
                             CatalogItem.self, Establishment.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        return ModelContext(container)
    }

    private func paidReceipt() throws -> (Establishment, ArchivedReceipt) {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let product = CatalogItem(establishmentID: shop.id, title: "Coupe", priceMinor: 4_000,
                                  isService: true)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
        order.state = .completed
        order.totalMinor = 4_000
        let line = OrderLine(orderID: order.id, catalogItemID: product.id, quantity: 1,
                             unitPriceMinor: 4_000)
        line.dishName = "Coupe"
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
                                    method: "MTN MoMo", amountMinor: 4_000, confirmedByID: owner)
        return (shop, try ArchivedReceipt(shop: shop, order: order, lines: [line],
                                          payments: [payment], catalog: [product]))
    }

    func testPaidReceiptCanBeArchivedAndImportedOnAnotherDevice() throws {
        let (sourceShop, archive) = try paidReceipt()
        let target = Establishment(id: sourceShop.id, ownerID: sourceShop.ownerID,
                                   name: sourceShop.name, kind: .salon, city: sourceShop.city)
        let db = try memory()
        db.insert(target)
        try archive.importIfNeeded(shop: target, context: db)
        try db.save()
        let orders = try db.fetch(FetchDescriptor<CommerceOrder>())
        XCTAssertEqual(orders.count, 1)
        XCTAssertEqual(orders[0].totalMinor, 4_000)
        XCTAssertEqual(try db.fetch(FetchDescriptor<OrderLine>()).first?.dishName, "Coupe")
        XCTAssertEqual(try db.fetch(FetchDescriptor<PaymentRecord>()).first?.method, "MTN MoMo")
    }

    func testReplayingCloudReceiptDoesNotDuplicatePayments() throws {
        let (shop, archive) = try paidReceipt()
        let db = try memory()
        db.insert(shop)
        try archive.importIfNeeded(shop: shop, context: db)
        try db.save()
        try archive.importIfNeeded(shop: shop, context: db)
        try db.save()
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CommerceOrder>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
    }

    func testReceiptFromAnotherBusinessIsRejected() throws {
        let (_, archive) = try paidReceipt()
        let unrelated = Establishment(ownerID: UUID(), name: "Autre", kind: .salon, city: "Libreville")
        let db = try memory()
        XCTAssertThrowsError(try archive.importIfNeeded(shop: unrelated, context: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CommerceOrder>()), 0)
    }

    func testArchiveRoundTripPreservesExactMinorUnits() throws {
        let (_, archive) = try paidReceipt()
        let bytes = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(ArchivedReceipt.self, from: bytes)
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.totalMinor, 4_000)
    }
}
