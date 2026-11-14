import Foundation
import Security

enum KeychainError: LocalizedError {
    case invalidData
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData: "Les données Keychain sont invalides."
        case .operationFailed(let status): "Erreur Keychain (\(status))."
        }
    }
}

struct KeychainStore {
    let service: String
    private let accessGroup: String?

    init(service: String = "com.covi.app.security", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func save(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.operationFailed(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.operationFailed(status)
        }
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.operationFailed(status) }
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return data
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.operationFailed(status) }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
