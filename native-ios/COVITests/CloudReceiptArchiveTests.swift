import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CloudReceiptArchiveTests: XCTestCase {
    private func memory() throws -> ModelContext {
        let schema = Schema([CommerceOrder.self, OrderLine.self, PaymentRecord.self,
                             CatalogItem.self, Establishment.self,
                             ExpenseEntry.self, PendingExpenseVoid.self])
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

    func testArchivedReceiptDetectsChangedCashierConfirmation() throws {
        let (shop, archive) = try paidReceipt()
        let db = try memory()
        db.insert(shop)
        try archive.importIfNeeded(shop: shop, context: db)
        try db.save()
        let payment = try XCTUnwrap(db.fetch(FetchDescriptor<PaymentRecord>()).first)
        payment.cashReceived = 7_000
        XCTAssertThrowsError(try archive.importIfNeeded(shop: shop, context: db))
    }

    func testArchivedReceiptDetectsChangedProductDescription() throws {
        let (shop, archive) = try paidReceipt()
        let db = try memory()
        db.insert(shop)
        try archive.importIfNeeded(shop: shop, context: db)
        try db.save()
        let article = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        article.dishName = "Article modifié"
        XCTAssertThrowsError(try archive.importIfNeeded(shop: shop, context: db))
    }

    func testExpenseCloudImportIsIdempotentAndPreservesAmount() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Pointe-Noire")
        let expense = ExpenseEntry(establishmentID: shop.id, actorID: owner,
            category: "Loyer", amountMinor: 35_000, spentAt: .now, note: "Local")
        let fact = CloudExpenseFact(shop: shop, entry: expense, action: .created)
        let db = try memory()
        db.insert(shop)
        try fact.apply(shop: shop, context: db)
        try db.save()
        try fact.apply(shop: shop, context: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<ExpenseEntry>()), 1)
        XCTAssertEqual(try db.fetch(FetchDescriptor<ExpenseEntry>()).first?.amountMinor, 35_000)
    }

    func testExpenseCloudVoidCanArriveBeforeOriginalEntry() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let expense = ExpenseEntry(establishmentID: shop.id, actorID: owner,
            category: "Transport", amountMinor: 2_500, spentAt: .now, note: "Bus")
        expense.voidedAt = .now
        expense.voidedByID = owner
        let created = CloudExpenseFact(shop: shop, entry: expense, action: .created)
        let voided = CloudExpenseFact(shop: shop, entry: expense, action: .voided)
        let db = try memory()
        db.insert(shop)
        try voided.apply(shop: shop, context: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PendingExpenseVoid>()), 1)
        try created.apply(shop: shop, context: db)
        try CloudExpenseLedger.resolvePending(shop: shop, context: db)
        try db.save()
        let imported = try XCTUnwrap(db.fetch(FetchDescriptor<ExpenseEntry>()).first)
        XCTAssertNotNil(imported.voidedAt)
        XCTAssertEqual(imported.voidedByID, owner)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PendingExpenseVoid>()), 0)
    }

    func testExpenseCloudRejectsWrongOwnerAndChangedAmount() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let expense = ExpenseEntry(establishmentID: shop.id, actorID: owner,
            category: "Eau", amountMinor: 8_000, spentAt: .now, note: "Facture")
        let fact = CloudExpenseFact(shop: shop, entry: expense, action: .created)
        let foreignOwner = Establishment(id: shop.id, ownerID: UUID(), name: shop.name,
                                         kind: .restaurant, city: shop.city)
        let db = try memory()
        db.insert(shop)
        XCTAssertThrowsError(try fact.apply(shop: foreignOwner, context: db))
        try fact.apply(shop: shop, context: db)
        try db.save()
        let imported = try XCTUnwrap(db.fetch(FetchDescriptor<ExpenseEntry>()).first)
        imported.amountMinor = 1_000
        XCTAssertThrowsError(try fact.apply(shop: shop, context: db))
    }

    func testExpenseVoidEventIdentifiersAreStableAndDistinct() {
        let id = UUID()
        let created = CloudExpenseFact.eventID(for: id, action: .created)
        let voided = CloudExpenseFact.eventID(for: id, action: .voided)
        XCTAssertEqual(created, id)
        XCTAssertNotEqual(created, voided)
        XCTAssertEqual(voided, CloudExpenseFact.eventID(for: id, action: .voided))
    }

    func testExpenseFactsHaveStableCanonicalRepresentation() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Libreville")
        let entry = ExpenseEntry(establishmentID: shop.id, actorID: owner,
            category: "Transport", amountMinor: 8_500, spentAt: .now, note: "Livraison")
        let fact = CloudExpenseFact(shop: shop, entry: entry, action: .created)
        let bytes = try fact.canonicalData()
        let decoded = try JSONDecoder().decode(CloudExpenseFact.self, from: bytes)
        XCTAssertEqual(try decoded.canonicalData(), bytes)
        XCTAssertEqual(decoded, fact)
    }

    func testExpenseCloudRefusesVoidsByUnknownAccounts() {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Douala")
        let expense = ExpenseEntry(establishmentID: shop.id, actorID: owner,
            category: "Eau", amountMinor: 1_500, spentAt: .now, note: "Facture")
        expense.voidedAt = .now.addingTimeInterval(60)
        expense.voidedByID = UUID()
        let fact = CloudExpenseFact(shop: shop, entry: expense, action: .voided)
        XCTAssertThrowsError(try fact.validate(shop: shop))
    }
}
