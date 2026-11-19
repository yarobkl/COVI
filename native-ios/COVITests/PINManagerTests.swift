import Foundation
import XCTest
@testable import COVI

/// Tests use an isolated Keychain service and a controllable clock.
/// They never read or modify the application's production PIN entries.
@MainActor
final class PINManagerTests: XCTestCase {
    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(by seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }

    private var service = ""
    private var keys: [String] = []
    private var store: KeychainStore!
    private var clock: TestClock!
    private let correctPIN = "1234"
    private let wrongPIN = "0000"

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = "com.covi.app.pin-tests.\(UUID().uuidString)"
        store = KeychainStore(service: service)
        clock = TestClock()
        keys = []
    }

    override func tearDownWithError() throws {
        for key in keys { try store.delete(key) }
        keys = []
        store = nil
        clock = nil
        try super.tearDownWithError()
    }

    private func makeManager() -> PINManager {
        let clock = self.clock!
        return PINManager(keychain: store, now: { clock.date })
    }

    private func configure(_ manager: PINManager, staff: UUID, shop: UUID) throws {
        keys.append("pin.cashier.\(shop.uuidString).\(staff.uuidString)")
        keys.append("pin.attempts.cashier.\(shop.uuidString).\(staff.uuidString)")
        try manager.configureCashierPIN(correctPIN, for: staff, shopID: shop)
    }

    func testLocksAfterFiveFailuresAndRejectsCorrectPINDuringLockout() throws {
        let staff = UUID(), shop = UUID()
        let manager = makeManager()
        try configure(manager, staff: staff, shop: shop)
        let scope = PINScope.cashier(staffID: staff, shopID: shop)

        for attempt in 1...5 {
            XCTAssertFalse(manager.verify(wrongPIN, scope: scope))
            if attempt < 5 {
                XCTAssertEqual(manager.failedAttempts, attempt)
                XCTAssertEqual(manager.lastError, .invalid)
            }
        }
        XCTAssertEqual(manager.failedAttempts, 0)
        XCTAssertEqual(manager.remainingLockout, 60, accuracy: 0.001)
        XCTAssertEqual(manager.lastError, .temporarilyLocked(until: clock.date.addingTimeInterval(60)))
        XCTAssertFalse(manager.verify(correctPIN, scope: scope))
        XCTAssertNil(manager.unlockedStaffID)
    }

    func testLockoutPersistsAcrossManagerRecreationAndExpires() throws {
        let staff = UUID(), shop = UUID()
        let manager = makeManager()
        try configure(manager, staff: staff, shop: shop)
        let scope = PINScope.cashier(staffID: staff, shopID: shop)
        for _ in 0..<5 { XCTAssertFalse(manager.verify(wrongPIN, scope: scope)) }

        let restored = makeManager()
        XCTAssertFalse(restored.verify(correctPIN, scope: scope))
        XCTAssertEqual(restored.remainingLockout, 60, accuracy: 0.001)

        clock.advance(by: 59)
        XCTAssertFalse(restored.verify(correctPIN, scope: scope))
        clock.advance(by: 1)
        XCTAssertTrue(restored.verify(correctPIN, scope: scope))
        XCTAssertEqual(restored.unlockedStaffID, staff)
        XCTAssertEqual(restored.failedAttempts, 0)
        XCTAssertEqual(restored.remainingLockout, 0, accuracy: 0.001)
    }

    func testFailedAttemptsPersistAcrossManagerRecreation() throws {
        let staff = UUID(), shop = UUID()
        let first = makeManager()
        try configure(first, staff: staff, shop: shop)
        let scope = PINScope.cashier(staffID: staff, shopID: shop)
        for _ in 0..<3 { XCTAssertFalse(first.verify(wrongPIN, scope: scope)) }

        let restored = makeManager()
        XCTAssertFalse(restored.verify(wrongPIN, scope: scope))
        XCTAssertEqual(restored.failedAttempts, 4)
        XCTAssertFalse(restored.verify(wrongPIN, scope: scope))
        XCTAssertEqual(restored.remainingLockout, 60, accuracy: 0.001)
    }

    func testCorruptPersistedAttemptStateFailsClosed() throws {
        let staff = UUID(), shop = UUID()
        let manager = makeManager()
        try configure(manager, staff: staff, shop: shop)
        let scope = PINScope.cashier(staffID: staff, shopID: shop)
        try store.save(Data("not-json".utf8),
                       for: "pin.attempts.cashier.\(shop.uuidString).\(staff.uuidString)")

        XCTAssertFalse(manager.verify(correctPIN, scope: scope))
        XCTAssertEqual(manager.lastError, .storageFailure)
        XCTAssertNil(manager.unlockedStaffID)
    }

    func testMissingAttemptStateStartsWithZeroFailures() throws {
        let staff = UUID(), shop = UUID()
        let manager = makeManager()
        try configure(manager, staff: staff, shop: shop)
        let scope = PINScope.cashier(staffID: staff, shopID: shop)

        XCTAssertTrue(manager.verify(correctPIN, scope: scope))
        XCTAssertEqual(manager.failedAttempts, 0)
        XCTAssertNil(manager.lockedUntil)
    }

    func testOwnerWithoutConfiguredCashierPINCanOperateImmediately() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Marché", kind: .boutique,
                                 city: "Brazzaville")
        let manager = makeManager()
        XCTAssertTrue(manager.mayOperate(shop: shop, actor: owner))
        XCTAssertFalse(manager.mayOperate(shop: shop, actor: UUID()))
    }

    func testConfiguredOwnerCashierPINRestoresTheLock() throws {
        let owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Marché", kind: .boutique,
                                 city: "Brazzaville")
        let manager = makeManager()
        try configure(manager, staff: owner, shop: shop.id)
        XCTAssertFalse(manager.mayOperate(shop: shop, actor: owner))
        XCTAssertTrue(manager.verify(correctPIN, scope: .cashier(staffID: owner, shopID: shop.id)))
        XCTAssertTrue(manager.mayOperate(shop: shop, actor: owner))
        manager.lock()
        XCTAssertFalse(manager.mayOperate(shop: shop, actor: owner))
    }

    func testCashierPINRejectsNonAsciiCharactersAndIncorrectLengths() throws {
        let manager = makeManager(), staff = UUID(), shop = UUID()
        for invalid in ["1", "12345", "12ab", "١٢٣٤"] {
            XCTAssertThrowsError(try manager.configureCashierPIN(invalid, for: staff, shopID: shop))
        }
    }

    func testVerificationRejectsUnicodeNumerals() throws {
        let staff = UUID(), shop = UUID()
        let manager = makeManager()
        try configure(manager, staff: staff, shop: shop)
        XCTAssertFalse(manager.verify("١٢٣٤", scope: .cashier(staffID: staff, shopID: shop)))
        XCTAssertEqual(manager.lastError, .malformed)
    }
}
