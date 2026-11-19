import CloudKit
import Foundation
import SwiftData

/// Petit index privé dans iCloud qui permet de retrouver les établissements
/// après une connexion Apple sur un second appareil. Aucune base web.
@MainActor enum CloudShopDirectory {
    enum DirectoryError: LocalizedError {
        case noICloud, invalidPayload, wrongAccount, tooManyShops, concurrentUpdate
        var errorDescription: String? {
            switch self {
            case .noICloud: "Connectez-vous à iCloud dans les réglages de l’iPhone."
            case .invalidPayload: "Le répertoire iCloud n'est pas compatible avec cette version de COVI."
            case .wrongAccount: "Le répertoire iCloud appartient à une autre identité COVI."
            case .tooManyShops: "La limite de trois établissements actifs est atteinte."
            case .concurrentUpdate: "Le répertoire a été modifié sur un autre appareil. Réessayez."
            }
        }
    }

    struct Entry: Codable, Equatable {
        let id: UUID
        let ownerID: UUID
        var name: String
        var kind: BusinessKind
        var city: String
        var currencyCode: String
        var archived: Bool
        var updatedAt: Date

        init(_ shop: Establishment) {
            id = shop.id
            ownerID = shop.ownerID
            name = shop.name
            kind = shop.kind
            city = shop.city
            currencyCode = shop.currencyCode
            archived = shop.archived
            updatedAt = shop.updatedAt
        }

        func apply(to shop: Establishment) {
            shop.name = name
            shop.kind = kind
            shop.city = city
            shop.currencyCode = currencyCode
            shop.archived = archived
            shop.updatedAt = updatedAt
        }
    }

    private struct Document: Codable {
        let version: Int
        let ownerID: UUID
        var shops: [Entry]
    }

    static func merge(local: [Entry], remote: [Entry]) -> [Entry] {
        var merged = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for entry in local {
            if let current = merged[entry.id] {
                if entry.updatedAt > current.updatedAt { merged[entry.id] = entry }
            } else { merged[entry.id] = entry }
        }
        return merged.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Fusion déterministe des établissements. L'absence sur un appareil ne supprime rien.
    /// Chaque création ou modification porte une date, mais les conflits simultanés nécessitent
    /// toujours une validation du propriétaire plutôt qu'une promesse de fusion magique.
    static func reconcile(owner: UUID, context: ModelContext) async throws {
        let container = CKContainer.default()
        guard try await container.accountStatus() == .available else { throw DirectoryError.noICloud }
        let database = container.privateCloudDatabase
        let key = CKRecord.ID(recordName: "COVIAccount-v1-\(owner.uuidString)")

        for _ in 0..<3 {
            try Task.checkCancellation()
            let record: CKRecord
            do {
                record = try await database.record(for: key)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "COVIAccountIndex", recordID: key)
            }
            let remote = try decode(record, owner: owner)
            let shopList = try context.fetch(FetchDescriptor<Establishment>(
                predicate: #Predicate { $0.ownerID == owner }
            ))

            let combined = merge(local: shopList.map { Entry($0) }, remote: remote.shops)
            guard combined.filter({ !$0.archived }).count <= 3 else { throw DirectoryError.tooManyShops }

            var didChange = false
            for entry in combined where entry.ownerID == owner {
                if let local = shopList.first(where: { $0.id == entry.id }) {
                    if entry.updatedAt > local.updatedAt {
                        entry.apply(to: local)
                        didChange = true
                    }
                } else {
                    let newShop = Establishment(id: entry.id, ownerID: owner, name: entry.name,
                                                kind: entry.kind, city: entry.city,
                                                currencyCode: entry.currencyCode)
                    entry.apply(to: newShop)
                    context.insert(newShop)
                    context.insert(Membership(accountID: owner, establishmentID: entry.id, role: .owner))
                    didChange = true
                }
            }
            if didChange { try context.save() }

            if combined == remote.shops.sorted(by: { $0.id.uuidString < $1.id.uuidString }) { return }
            let updated = Document(version: 1, ownerID: owner, shops: combined)
            record["payload"] = try JSONEncoder().encode(updated) as NSData
            do {
                _ = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }
        throw DirectoryError.concurrentUpdate
    }

    private static func decode(_ record: CKRecord, owner: UUID) throws -> Document {
        guard let bytes = record["payload"] as? Data else {
            return Document(version: 1, ownerID: owner, shops: [])
        }
        guard let data = try? JSONDecoder().decode(Document.self, from: bytes),
              data.version == 1 else { throw DirectoryError.invalidPayload }
        guard data.ownerID == owner, data.shops.allSatisfy({ $0.ownerID == owner }) else {
            throw DirectoryError.wrongAccount
        }
        guard Set(data.shops.map(\.id)).count == data.shops.count else {
            throw DirectoryError.invalidPayload
        }
        return data
    }
}
