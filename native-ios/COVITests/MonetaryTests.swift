import XCTest
@testable import COVI

@MainActor
final class MonetaryTests: XCTestCase {
    private func product(_ price: Int64) -> CatalogItem {
        CatalogItem(establishmentID: UUID(), title: "Article test", priceMinor: price)
    }

    func testExactFCFATotal() throws {
        let lines = [BoutiqueLedger.Line(product: product(1_500), units: 3)]
        XCTAssertEqual(try BoutiqueLedger.total(lines, discount: 0), 4_500)
    }

    func testDiscountInFCFA() throws {
        let lines = [BoutiqueLedger.Line(product: product(10_000), units: 1)]
        XCTAssertEqual(try BoutiqueLedger.total(lines, discount: 1_000), 9_000)
    }

    func testMultiplicationOverflowIsRejected() {
        let lines = [BoutiqueLedger.Line(product: product(Int64.max), units: 2)]
        XCTAssertThrowsError(try BoutiqueLedger.total(lines, discount: 0))
    }

    func testAdditionOverflowIsRejected() {
        let lines = [
            BoutiqueLedger.Line(product: product(Int64.max), units: 1),
            BoutiqueLedger.Line(product: product(1), units: 1)
        ]
        XCTAssertThrowsError(try BoutiqueLedger.total(lines, discount: 0))
    }

    func testNegativeDiscountIsRejected() {
        XCTAssertThrowsError(try BoutiqueLedger.total(
            [BoutiqueLedger.Line(product: product(1_000), units: 1)], discount: -1
        ))
    }

    func testZeroOrNegativeQuantityIsRejected() {
        for units in [0, -1] {
            XCTAssertThrowsError(try BoutiqueLedger.total(
                [BoutiqueLedger.Line(product: product(1_000), units: units)], discount: 0
            ))
        }
    }

    func testDiscountCannotExceedOrEqualTotal() {
        let lines = [BoutiqueLedger.Line(product: product(1_000), units: 1)]
        XCTAssertThrowsError(try BoutiqueLedger.total(lines, discount: 1_000))
        XCTAssertThrowsError(try BoutiqueLedger.total(lines, discount: 1_001))
    }
}
