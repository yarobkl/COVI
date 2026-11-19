import Foundation
import XCTest
@testable import COVI

/// XCTest is intentionally unsigned in the diagnostic workflow. Use a local
/// deterministic storage fake; on-device checks still exercise KeychainStore.
final class InMemorySecureStore: SecureStorage {
    private var entries: [String: Data] = [:]
    func save(_ data: Data, for key: String) throws { entries[key] = data }
    func data(for key: String) throws -> Data? { entries[key] }
    func delete(_ key: String) throws { entries.removeValue(forKey: key) }
}

struct UnavailableSecureStore: SecureStorage {
    enum Failure: Error { case inaccessible }
    func save(_ data: Data, for key: String) throws { throw Failure.inaccessible }
    func data(for key: String) throws -> Data? { throw Failure.inaccessible }
    func delete(_ key: String) throws { throw Failure.inaccessible }
}

@MainActor
final class NativeSessionTests: XCTestCase {
    private var store: InMemorySecureStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = InMemorySecureStore()
    }

    override func tearDownWithError() throws {
        try store.delete("session.native.identity")
        try store.delete("session.native.local")
        store = nil
        try super.tearDownWithError()
    }

    func testLocalIdentityPersistsAcrossAppSessions() throws {
        let first = AppSession(keychain: store)
        try first.createLocalAccount(name: "  Rodrin  ", email: "rodrin@example.test")
        let identifier = try XCTUnwrap(first.accountID)
        XCTAssertEqual(first.displayName, "Rodrin")
        XCTAssertFalse(first.usesAppleAccount)
        try first.signOut()
        XCTAssertNil(first.accountID)

        let second = AppSession(keychain: store)
        try second.continueLocally()
        XCTAssertEqual(second.accountID, identifier)
        XCTAssertEqual(second.email, "rodrin@example.test")
    }

    func testLocalModeRestoresWithoutNetwork() async throws {
        let original = AppSession(keychain: store)
        try original.createLocalAccount(name: "Commerçant")
        let restored = AppSession(keychain: store)
        try await restored.restore()
        XCTAssertEqual(restored.accountID, original.accountID)
        XCTAssertFalse(restored.usesAppleAccount)
    }

    func testNoLocalAccountFailsWithoutCreatingPhantomIdentity() throws {
        let session = AppSession(keychain: store)
        XCTAssertThrowsError(try session.continueLocally())
        XCTAssertNil(session.accountID)
    }

    func testEmptyLocalNameIsRejected() throws {
        let session = AppSession(keychain: store)
        XCTAssertThrowsError(try session.createLocalAccount(name: "  "))
        XCTAssertNil(session.accountID)
    }

    func testAppleIdentifierStableAndDifferentForDifferentUsers() {
        let first = AppSession.accountIdentifier(for: "apple-user-1")
        let again = AppSession.accountIdentifier(for: "apple-user-1")
        let second = AppSession.accountIdentifier(for: "apple-user-2")
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, second)
    }

    func testLocalDisplayNameUpdateIsPersisted() throws {
        let session = AppSession(keychain: store)
        try session.createLocalAccount(name: "Ancien nom")
        try session.updateDisplayName("  Nouveau nom  ")
        XCTAssertEqual(session.displayName, "Nouveau nom")
        try session.signOut()
        let reopened = AppSession(keychain: store)
        try reopened.continueLocally()
        XCTAssertEqual(reopened.displayName, "Nouveau nom")
    }

    func testEmptyNameUpdateDoesNotReplaceExistingProfile() throws {
        let session = AppSession(keychain: store)
        try session.createLocalAccount(name: "Nom valide")
        XCTAssertThrowsError(try session.updateDisplayName(" "))
        XCTAssertEqual(session.displayName, "Nom valide")
    }

    func testUnavailableSecureStoreNeverCreatesAUserSession() {
        let session = AppSession(keychain: UnavailableSecureStore())
        XCTAssertThrowsError(try session.createLocalAccount(name: "Commerce"))
        XCTAssertNil(session.accountID)
        XCTAssertThrowsError(try session.continueLocally())
        XCTAssertNil(session.accountID)
    }
}
