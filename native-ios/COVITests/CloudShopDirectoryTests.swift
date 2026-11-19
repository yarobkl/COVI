import Foundation
import XCTest
@testable import COVI

@MainActor
final class CloudShopDirectoryTests: XCTestCase {
    private let owner = UUID()

    private func entry(name: String, id: UUID = UUID(), at date: Date) -> CloudShopDirectory.Entry {
        let shop = Establishment(id: id, ownerID: owner, name: name, kind: .boutique,
                                 city: "Brazzaville", currencyCode: "XAF")
        shop.updatedAt = date
        return CloudShopDirectory.Entry(shop)
    }

    func testRemoteOnlyShopIsKeptOnNewDevice() {
        let remote = entry(name: "Boutique du centre", at: .now)
        XCTAssertEqual(CloudShopDirectory.merge(local: [], remote: [remote]), [remote])
    }

    func testLocalOnlyShopIsUploaded() {
        let local = entry(name: "Salon du quartier", at: .now)
        XCTAssertEqual(CloudShopDirectory.merge(local: [local], remote: []), [local])
    }

    func testRemoteEditWinsWhenItIsNewer() {
        let id = UUID(), original = Date(timeIntervalSince1970: 1_700_000_000)
        let local = entry(name: "Ancien nom", id: id, at: original)
        let remote = entry(name: "Nouveau nom", id: id, at: original.addingTimeInterval(10))
        XCTAssertEqual(CloudShopDirectory.merge(local: [local], remote: [remote]), [remote])
    }

    func testLocalEditWinsWhenItIsNewer() {
        let id = UUID(), original = Date(timeIntervalSince1970: 1_700_000_000)
        let local = entry(name: "Nouveau nom", id: id, at: original.addingTimeInterval(10))
        let remote = entry(name: "Ancien nom", id: id, at: original)
        XCTAssertEqual(CloudShopDirectory.merge(local: [local], remote: [remote]), [local])
    }

    func testMergeIsIdempotentAndDeduplicates() {
        let first = entry(name: "Boutique", at: .now)
        let second = entry(name: "Restaurant", at: .now)
        let once = CloudShopDirectory.merge(local: [first], remote: [first, second])
        XCTAssertEqual(once.count, 2)
        XCTAssertEqual(CloudShopDirectory.merge(local: once, remote: once), once)
    }
}
