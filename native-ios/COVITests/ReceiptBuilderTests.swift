import XCTest
import PDFKit
import UIKit
@testable import COVI

@MainActor
final class ReceiptBuilderTests: XCTestCase {
    private let owner = UUID()

    private func fixture() -> (shop: Establishment, item: CatalogItem, order: CommerceOrder,
                               lines: [OrderLine], payment: PaymentRecord) {
        let shop = Establishment(ownerID: owner, name: "Boutique COVI", kind: .boutique,
                                 city: "Brazzaville")
        let product = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 2_000)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
        order.state = .completed
        order.totalMinor = 3_500
        order.discountMinor = 500
        let line = OrderLine(orderID: order.id, catalogItemID: product.id, quantity: 2,
                             unitPriceMinor: 2_000)
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
                                    method: "Espèces", amountMinor: 3_500, confirmedByID: owner)
        return (shop, product, order, [line], payment)
    }

    func testReceiptUsesConfirmedAmountsAndOriginalUnitPrices() throws {
        let fixture = fixture()
        let receipt = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment])
        XCTAssertEqual(receipt.subtotalMinor, 4_000)
        XCTAssertEqual(receipt.discountMinor, 500)
        XCTAssertEqual(receipt.totalMinor, 3_500)
        XCTAssertTrue(receipt.shareText.contains("Boutique COVI"))
        XCTAssertTrue(receipt.shareText.contains("Riz"))
        XCTAssertTrue(receipt.shareText.contains("Paiement confirmé en caisse"))
    }

    func testNoUnconfirmedReceiptCanBeShared() {
        let fixture = fixture()
        XCTAssertThrowsError(try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: []))
    }

    func testCrossEstablishmentPaymentsAreNotAccepted() {
        let fixture = fixture()
        let foreign = PaymentRecord(orderID: fixture.order.id, establishmentID: UUID(),
                                    method: "Espèces", amountMinor: 3_500, confirmedByID: owner)
        XCTAssertThrowsError(try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [foreign]))
    }

    func testIncorrectTotalIsRejected() {
        let fixture = fixture()
        fixture.order.totalMinor = 3_600
        XCTAssertThrowsError(try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment]))
    }

    func testInt64OverflowInLineTotalIsRejected() {
        let fixture = fixture()
        fixture.lines[0].unitPriceMinor = Int64.max
        XCTAssertThrowsError(try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment]))
    }

    func testRefundAppearsInSharedReceiptWithoutRemovingOriginalPayment() throws {
        let fixture = fixture()
        let refund = Refund(payment: fixture.payment, ownerID: owner)
        let summary = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment], refunds: [refund])
        XCTAssertEqual(summary.totalMinor, 3_500)
        XCTAssertEqual(summary.refundedMinor, 3_500)
        XCTAssertTrue(summary.shareText.contains("REMBOURSEMENT CONFIRMÉ"))
    }

    func testRefundFromWrongOwnerIsRejected() {
        let fixture = fixture()
        let refund = Refund(payment: fixture.payment, ownerID: UUID())
        XCTAssertThrowsError(try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment], refunds: [refund]))
    }

    func testNativeReceiptImageIsReadablePNGAndLeavesNoTemporaryPDF() throws {
        let fixture = fixture()
        let summary = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment])
        let urls = try ReceiptImageExporter.export(summary)
        defer { for file in urls { try? FileManager.default.removeItem(at: file) } }
        XCTAssertEqual(urls.count, 1)
        let file = try XCTUnwrap(urls.first)
        XCTAssertEqual(file.pathExtension, "png")
        let image = try XCTUnwrap(UIImage(contentsOfFile: file.path))
        XCTAssertEqual(image.cgImage?.width, 1_190)
        XCTAssertEqual(image.cgImage?.height, 1_684)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertFalse(siblings.contains { $0.hasPrefix("COVI-recu-" + summary.orderID.uuidString) && $0.hasSuffix(".pdf") })
    }

    func testReceiptImageIncludesEveryPageOfLongReceipt() throws {
        let fixture = fixture()
        fixture.order.discountMinor = 0
        fixture.order.totalMinor = 160_000
        fixture.payment.amountMinor = 160_000
        let lines = (0..<80).map { index in
            let line = OrderLine(orderID: fixture.order.id, catalogItemID: fixture.item.id,
                quantity: 1, unitPriceMinor: 2_000)
            line.dishName = "Article \(index + 1)"
            return line
        }
        let summary = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: lines, products: [fixture.item], payments: [fixture.payment])
        let pdf = try ReceiptPDFExporter.export(summary)
        defer { try? FileManager.default.removeItem(at: pdf) }
        let expectedPages = try XCTUnwrap(PDFDocument(url: pdf)).pageCount
        XCTAssertGreaterThan(expectedPages, 1)
        let images = try ReceiptImageExporter.export(summary)
        defer { for file in images { try? FileManager.default.removeItem(at: file) } }
        XCTAssertEqual(images.count, expectedPages)
        XCTAssertEqual(Set(images).count, expectedPages)
        for file in images { XCTAssertNotNil(UIImage(contentsOfFile: file.path)) }
    }

    func testNativePDFContainsConfirmedReceiptInformation() throws {
        let fixture = fixture()
        let summary = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment])
        let url = try ReceiptPDFExporter.export(summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("Boutique COVI") == true)
        XCTAssertTrue(document.string?.contains("3500") == true)
    }

    func testCentralAfricanCurrenciesAreExplicitAndReceiptKeepsShopCurrency() throws {
        XCTAssertTrue(SupportedCurrency.allows("XAF"))
        XCTAssertTrue(SupportedCurrency.allows("CDF"))
        XCTAssertTrue(SupportedCurrency.allows("RWF"))
        XCTAssertTrue(SupportedCurrency.allows("BIF"))
        XCTAssertFalse(SupportedCurrency.allows("USD"))
        let fixture = fixture()
        fixture.shop.currencyCode = "CDF"
        let receipt = try ReceiptBuilder.create(order: fixture.order, shop: fixture.shop,
            lines: fixture.lines, products: [fixture.item], payments: [fixture.payment])
        XCTAssertEqual(receipt.currencyCode, "CDF")
        XCTAssertTrue(receipt.shareText.contains("CDF"))
        XCTAssertFalse(receipt.shareText.contains("FCFA"))
    }
}
