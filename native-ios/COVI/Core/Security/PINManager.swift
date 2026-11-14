import Foundation
import CryptoKit
import Observation

struct PINVerifier: Codable, Sendable {
    let salt: Data
    let digest: Data
    let iterations: Int
}

enum PINScope: Sendable {
    case master(ownerID: UUID)
    case cashier(staffID: UUID, shopID: UUID)
}

@MainActor @Observable final class PINManager {
    private(set) var unlockedStaffID: UUID?
    private(set) var failedAttempts = 0
    private(set) var lockedUntil: Date?
    private(set) var lastError: PINError?

    private var lastActivity = Date.distantPast
    private let inactivityTimeout: TimeInterval = 120
    private let maxAttempts = 5
    private let lockoutDuration: TimeInterval = 60
    private let keychain: KeychainStore

    enum PINError: LocalizedError, Equatable {
        case malformed
        case notConfigured
        case invalid
        case temporarilyLocked(until: Date)
        case storageFailure

        var errorDescription: String? {
            switch self {
            case .malformed: "Saisissez exactement 4 chiffres."
            case .notConfigured: "Aucun code PIN n’est configuré pour cette caisse."
            case .invalid: "Code PIN incorrect."
            case .temporarilyLocked(let until): "Caisse verrouillée jusqu’à \(until.formatted(date: .omitted, time: .shortened))."
            case .storageFailure: "Impossible d’accéder au stockage sécurisé."
            }
        }
    }

    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    var isUnlocked: Bool {
        guard unlockedStaffID != nil else { return false }
        return Date().timeIntervalSince(lastActivity) < inactivityTimeout
    }

    var remainingLockout: TimeInterval { max(0, lockedUntil?.timeIntervalSinceNow ?? 0) }

    func configureMasterPIN(_ pin: String, ownerID: UUID) throws {
        let key = "pin.master.\(ownerID.uuidString)"
        guard try keychain.data(for: key) == nil, pin.utf8.count == 4,
              pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw PINError.invalid }
        try saveVerifier(makeVerifier(for: pin), key: key)
    }

    func configureCashierPIN(_ pin: String, for staffID: UUID, shopID: UUID) throws {
        try saveVerifier(makeVerifier(for: pin), key: cashierKey(staffID, shopID))
    }

    func hasConfiguredPIN(for scope: PINScope) -> Bool { (try? verifier(for: scope)) != nil }

    @discardableResult
    func verify(_ input: String, scope: PINScope) -> Bool {
        lastError = nil
        guard input.count == 4, input.allSatisfy(\.isNumber) else { lastError = .malformed; return false }
        if let lockedUntil, Date() < lockedUntil {
            lastError = .temporarilyLocked(until: lockedUntil)
            return false
        }
        let verifier: PINVerifier
        do {
            guard let stored = try self.verifier(for: scope) else { lastError = .notConfigured; return false }
            verifier = stored
        } catch {
            lastError = .storageFailure
            return false
        }
        let candidate = Self.derive(pin: input, salt: verifier.salt, iterations: verifier.iterations)
        guard Self.constantTimeEqual(candidate, verifier.digest) else {
            registerFailure(); lastError = .invalid; return false
        }
        failedAttempts = 0
        lockedUntil = nil
        if case .cashier(let staffID, _) = scope { unlockedStaffID = staffID; lastActivity = .now }
        return true
    }

    func lock() { unlockedStaffID = nil; lastActivity = .distantPast }
    func touch() { if isUnlocked { lastActivity = .now } else { lock() } }

    private func registerFailure() {
        failedAttempts += 1
        if failedAttempts >= maxAttempts {
            lockedUntil = Date().addingTimeInterval(lockoutDuration)
            failedAttempts = 0
        }
    }

    private func verifier(for scope: PINScope) throws -> PINVerifier? {
        let key: String
        switch scope {
        case .master(let ownerID): key = "pin.master.\(ownerID.uuidString)"
        case .cashier(let staffID, let shopID): key = cashierKey(staffID, shopID)
        }
        guard let data = try keychain.data(for: key) else { return nil }
        return try JSONDecoder().decode(PINVerifier.self, from: data)
    }

    private func saveVerifier(_ verifier: PINVerifier, key: String) throws {
        do { try keychain.save(JSONEncoder().encode(verifier), for: key) }
        catch { throw PINError.storageFailure }
    }

    private func makeVerifier(for pin: String) -> PINVerifier {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let iterations = 100_000
        return PINVerifier(salt: salt, digest: Self.derive(pin: pin, salt: salt, iterations: iterations), iterations: iterations)
    }

    private func cashierKey(_ staffID: UUID, _ shopID: UUID) -> String { "pin.cashier.\(shopID.uuidString).\(staffID.uuidString)" }

    private static func derive(pin: String, salt: Data, iterations: Int) -> Data {
        var digest = Data(salt + Data(pin.utf8))
        for _ in 0..<iterations { digest = Data(SHA256.hash(data: digest + salt + Data(pin.utf8))) }
        return digest
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
