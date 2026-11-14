import CloudKit
import SwiftData
import SwiftUI

enum SyncFault: Error { case invalidEvent, journalChanged, accountChanged }

@Model final class SyncCheckpoint {
    @Attribute(.unique) var shopID: UUID
    var cloudUser: String
    var token: Data?
    init(shopID: UUID, cloudUser: String) {
        self.shopID = shopID
        self.cloudUser = cloudUser
    }
}

struct ShopChange: Codable {
    enum Kind: String, Codable { case rename, refund }
    let kind: Kind
    let owner: UUID
    let shop: UUID
    let entity: UUID
    let revision: Int64
    let name: String?
    let amount: Int64?
    let date: Date
}

@MainActor enum SyncCoordinator {
    static func history(_ shop: UUID, _ context: ModelContext) throws -> [OutboxEvent] {
        try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate {
            $0.establishmentID == shop && $0.eventType == "shop.v1"
        }, sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Caller saves the domain mutation and this event together.
    static func enqueue(_ kind: ShopChange.Kind, shop: Establishment, payment: PaymentRecord? = nil,
                        in context: ModelContext) throws {
        let entity = payment?.id ?? shop.id
        let changes = try history(shop.id, context).filter { $0.entityID == entity }
        let revision = try changes.map { try JSONDecoder().decode(ShopChange.self, from: $0.payloadJSON).revision }.max() ?? 0
        guard revision < Int64.max else { throw SyncFault.invalidEvent }
        let change = ShopChange(kind: kind, owner: shop.ownerID, shop: shop.id, entity: entity,
                                revision: revision + 1, name: kind == .rename ? shop.name : nil,
                                amount: payment?.amountMinor, date: .now)
        context.insert(OutboxEvent(establishmentID: shop.id, entityID: entity, eventType: "shop.v1",
                                   payloadJSON: try JSONEncoder().encode(change)))
    }

    static func cycle(shop: Establishment, context: ModelContext) async throws {
        let cloud = CloudKitAdapter(owner: shop.ownerID, shop: shop.id)
        let identity = try await cloud.container.userRecordID().recordName
        try Task.checkCancellation()
        let id = shop.id
        let checkpoints = try context.fetch(FetchDescriptor<SyncCheckpoint>(predicate: #Predicate { $0.shopID == id }))
        let checkpoint = checkpoints.first ?? SyncCheckpoint(shopID: id, cloudUser: identity)
        guard checkpoint.cloudUser == identity else { throw SyncFault.accountChanged }
        if checkpoints.isEmpty { context.insert(checkpoint); try context.save() }
        try await cloud.prepare()
        for event in try history(id, context) where event.state == .pending {
            try Task.checkCancellation()
            try await cloud.push(id: event.id, bytes: event.payloadJSON)
            try Task.checkCancellation()
            event.state = .synced
            try context.save()
        }
        while true {
            try Task.checkCancellation()
            do {
                let page = try await cloud.page(after: checkpoint.token)
                try Task.checkCancellation()
                do {
                    for (key, bytes) in page.events {
                        try apply(key, bytes, shop: shop, context: context)
                    }
                    checkpoint.token = page.token
                    try context.save()
                } catch { context.rollback(); throw error }
                if !page.more { return }
            } catch let error as CKError where error.code == .changeTokenExpired && checkpoint.token != nil {
                checkpoint.token = nil
                try context.save()
            }
        }
    }

    private static func apply(_ id: UUID, _ bytes: Data, shop: Establishment, context: ModelContext) throws {
        let change = try JSONDecoder().decode(ShopChange.self, from: bytes)
        guard change.shop == shop.id, change.owner == shop.ownerID, change.revision > 0 else { throw SyncFault.invalidEvent }
        let events = try history(shop.id, context)
        if let known = events.first(where: { $0.id == id }) {
            guard known.payloadJSON == bytes else { throw SyncFault.journalChanged }
            return
        }
        let event = OutboxEvent(establishmentID: shop.id, entityID: change.entity, eventType: "shop.v1", payloadJSON: bytes)
        event.id = id
        event.state = .synced
        switch change.kind {
        case .rename:
            guard change.entity == shop.id, let name = change.name, !name.isEmpty else { throw SyncFault.invalidEvent }
            let newerExists = try events.contains { row in
                let other = try JSONDecoder().decode(ShopChange.self, from: row.payloadJSON)
                return other.kind == .rename && (other.revision, row.id.uuidString) > (change.revision, id.uuidString)
            }
            if !newerExists { shop.name = name; shop.updatedAt = change.date }
        case .refund:
            guard let amount = change.amount, amount > 0 else { throw SyncFault.invalidEvent }
            let paymentID = change.entity
            let prior = try context.fetch(FetchDescriptor<Refund>(predicate: #Predicate { $0.paymentID == paymentID })).first
            if let prior {
                if prior.amountMinor != amount || prior.establishmentID != shop.id { event.state = .conflict }
            } else {
                context.insert(Refund(paymentID: paymentID, establishmentID: shop.id, ownerID: change.owner,
                                      amountMinor: amount, date: change.date))
            }
        }
        context.insert(event)
    }
}

struct ShopSyncStatus: View {
    let shop: Establishment
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var status = "Synchronisation en attente"
    var body: some View {
        Text(status).font(.caption).task(id: "\(shop.id)-\(phase)") {
            guard phase == .active else { return }
            var delay = 2.0
            while !Task.isCancelled {
                var wait = 15.0
                do {
                    try await SyncCoordinator.cycle(shop: shop, context: context)
                    let conflict = try SyncCoordinator.history(shop.id, context).contains { $0.state == .conflict }
                    status = conflict ? "Remboursement à vérifier" : "Synchronisé"
                    delay = 2
                } catch is CancellationError { return }
                catch {
                    status = "Synchronisation suspendue · données conservées"
                    wait = max(delay, (error as? CKError)?.retryAfterSeconds ?? 0)
                    delay = min(300, delay * 2)
                }
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
        }
    }
}
