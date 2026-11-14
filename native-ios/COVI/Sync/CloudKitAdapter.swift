import CloudKit

/// Append-only journal. Only the owning COVI account opens a private zone.
struct CloudKitAdapter {
    let container: CKContainer
    let zone: CKRecordZone
    var database: CKDatabase { container.privateCloudDatabase }

    init(owner: UUID, shop: UUID) {
        container = CKContainer.default()
        zone = CKRecordZone(zoneName: "COVI-\(owner.uuidString)-\(shop.uuidString)")
    }

    func prepare() async throws {
        _ = try await database.save(zone)
    }

    func push(id: UUID, bytes: Data) async throws {
        let key = CKRecord.ID(recordName: id.uuidString, zoneID: zone.zoneID)
        let record = CKRecord(recordType: "COVIEvent", recordID: key)
        record["payload"] = bytes as NSData
        do {
            let result = try await database.modifyRecords(saving: [record], deleting: [],
                savePolicy: .ifServerRecordUnchanged, atomically: true)
            guard let saved = result.saveResults[key] else { throw SyncFault.invalidEvent }
            _ = try saved.get()
        } catch {
            // The last upload may already have committed before the network failed.
            let original = error
            guard let existing = try? await database.record(for: key),
                  existing["payload"] as? Data == bytes else { throw original }
        }
    }

    func page(after bytes: Data?) async throws -> (events: [(UUID, Data)], token: Data, more: Bool) {
        var token: CKServerChangeToken?
        if let bytes {
            token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: bytes)
            guard token != nil else { throw SyncFault.invalidEvent }
        }
        let page = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token, resultsLimit: 100)
        guard page.deletions.isEmpty else { throw SyncFault.journalChanged }
        let events = try page.modificationResultsByID.map { key, result -> (UUID, Data) in
            let record = try result.get().record
            guard record.recordType == "COVIEvent", let id = UUID(uuidString: key.recordName),
                  let payload = record["payload"] as? Data else { throw SyncFault.invalidEvent }
            return (id, payload)
        }
        return (events, try NSKeyedArchiver.archivedData(withRootObject: page.changeToken,
                                                         requiringSecureCoding: true), page.moreComing)
    }
}
