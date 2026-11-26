import Foundation
import UIKit
import XCTest
@testable import COVI

final class BoutiqueArrivalTests: XCTestCase {
    func testQueuePersists450PhotosAndSeparatesShopsAndOrigins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shop = UUID()
        let store = BoutiqueArrivalStore(shopID: shop, origin: .bale, root: root)
        XCTAssertTrue(try store.pending().isEmpty)
        XCTAssertThrowsError(try store.save(Data()))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image {
            $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let bytes = try XCTUnwrap(image.pngData())
        for _ in 0..<450 { try store.save(bytes) }
        let reopened = BoutiqueArrivalStore(shopID: shop, origin: .bale, root: root)
        let pending = try reopened.pending()
        XCTAssertEqual(pending.count, 450)
        XCTAssertEqual(Set(pending.map(\.id)).count, 450)
        let first = try XCTUnwrap(pending.first)
        XCTAssertEqual(try Data(contentsOf: first.url), bytes)
        XCTAssertTrue(try BoutiqueArrivalStore(shopID: shop, origin: .supplier, root: root).pending().isEmpty)
        XCTAssertTrue(try BoutiqueArrivalStore(shopID: UUID(), origin: .bale, root: root).pending().isEmpty)
        try FileManager.default.removeItem(at: first.url)
        XCTAssertEqual(try reopened.pending().count, 449)
    }
}
