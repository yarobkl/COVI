import CloudKit
import Foundation
import SwiftData

/// Snapshots of operational state. Payments and refunds have their own verified,
/// immutable ledgers; they must never be inferred from a remote table or order.
struct OperationalCloudRow: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case catalog, bale, stockMovement, client, staff, visit, table, activeOrder,
             kitchenLine, salonSale, membership

        var priority: Int {
            switch self {
            case .catalog: 0
            case .staff, .client, .bale, .membership: 1
            case .activeOrder: 2
            case .table, .kitchenLine, .visit: 3
            case .stockMovement, .salonSale: 4
            }
        }

        var immutable: Bool {
            self == .bale || self == .stockMovement || self == .salonSale
        }
    }

    let version: Int
    let ownerID: UUID
    let shopID: UUID
    let kind: Kind
    let entityID: UUID
    let state: Data

    var key: String { shopID.uuidString + "-" + kind.rawValue + "-" + entityID.uuidString }

    func bytes() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    func validate(shop: Establishment) throws {
        guard version == 1, ownerID == shop.ownerID, shopID == shop.id,
              !state.isEmpty else { throw SyncFault.invalidEvent }
    }
}

struct OperationalCatalog: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let title: String
    let price: Int64
    let service: Bool
    let commission: Int
    let menuCategory: String?
    let unavailable: Bool
    let reserved: Int
    let updated: Date
    init(_ row: CatalogItem) {
        id = row.id; shop = row.establishmentID; title = row.title
        price = row.priceMinor; service = row.isService; commission = row.salonPercent
        menuCategory = row.menuCategory; unavailable = row.soldOut
        reserved = row.stockReserved; updated = row.updatedAt
    }
}

struct OperationalStock: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let item: UUID
    let delta: Int
    let bale: UUID?
    let reason: String
    let actor: UUID
    let date: Date
    init(_ row: StockMovement) {
        id = row.id; shop = row.establishmentID; item = row.itemID
        delta = row.delta; bale = row.baleID; reason = row.reason
        actor = row.actorID; date = row.createdAt
    }
}

struct OperationalBale: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let label: String
    let cost: Int64
    let received: Date
    init(_ row: Bale) {
        id = row.id; shop = row.shop; label = row.label
        cost = row.cost; received = row.received
    }
}

struct OperationalClient: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let name: String
    let phone: String
    let notes: String
    let preferences: String
    init(_ row: SalonClient) {
        id = row.id; shop = row.shop; name = row.name; phone = row.phone
        notes = row.notes; preferences = row.preferences
    }
}

struct OperationalStaff: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let name: String
    let active: Bool
    init(_ row: SalonStaff) {
        id = row.id; shop = row.shop; name = row.name; active = row.active
    }
}

struct OperationalVisit: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let client: UUID
    let service: UUID
    let stylist: String
    let start: Date
    let end: Date
    let walkIn: Bool
    let cancelled: Bool
    let receipt: UUID?
    init(_ row: SalonVisit) {
        id = row.id; shop = row.shop; client = row.client; service = row.service
        stylist = row.stylist; start = row.start; end = row.end
        walkIn = row.walkIn; cancelled = row.cancelled; receipt = row.receipt
    }
}

struct OperationalTable: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let label: String
    let capacity: Int
    let occupied: Bool
    let session: UUID?
    let lastReleasedSession: UUID?
    let billRequested: Bool
    init(_ row: DiningTable) {
        id = row.id; shop = row.establishmentID; label = row.label
        capacity = row.capacity; occupied = row.isOccupied
        session = row.activeSessionID; billRequested = row.billRequested
        lastReleasedSession = row.lastReleasedSessionID
    }
}

struct OperationalOrder: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let table: UUID?
    let customer: UUID?
    let guestCount: Int?
    let actor: UUID
    let state: String
    let created: Date
    let total: Int64
    let discount: Int64
    init(_ row: CommerceOrder) {
        id = row.id; shop = row.establishmentID; table = row.tableID
        customer = row.customerID; guestCount = row.restaurantGuestCount; actor = row.createdByID
        state = row.stateRaw; created = row.createdAt
        total = row.totalMinor; discount = row.discountMinor
    }
}

struct OperationalKitchenLine: Codable, Equatable {
    let id: UUID
    let order: UUID
    let item: UUID
    let quantity: Int
    let price: Int64
    let name: String?
    let preparation: String?
    let awaitingClaim: Bool?
    let sentAt: Date?

    var localPreparation: String? { awaitingClaim == true ? Prep.received.rawValue : preparation }
    init(_ row: OrderLine) {
        id = row.id; order = row.orderID; item = row.catalogItemID
        quantity = row.quantity; price = row.unitPriceMinor
        name = row.dishName
        // Keep the existing transport status readable by older installations.
        let received = row.preparation == Prep.received.rawValue
        preparation = received ? Prep.cooking.rawValue : row.preparation
        awaitingClaim = received ? true : nil
        sentAt = row.sentAt
    }
}

struct OperationalSalonSale: Codable, Equatable {
    let id: UUID
    let shop: UUID
    let order: UUID
    let client: UUID
    let stylist: String
    let title: String
    let service: Bool
    let units: Int
    let gross: Int64
    let percent: Int
    let commission: Int64
    let date: Date
    init(_ row: SalonSaleLine) {
        id = row.id; shop = row.shop; order = row.order; client = row.client
        stylist = row.stylist; title = row.title; service = row.service
        units = row.units; gross = row.gross; percent = row.percent
        commission = row.commission; date = row.date
    }
}

struct OperationalMembership: Codable, Equatable {
    let id: UUID
    let account: UUID
    let shop: UUID
    let role: String
    let active: Bool
    init(_ row: Membership) {
        id = row.id; account = row.accountID; shop = row.establishmentID
        role = row.roleRaw; active = row.active
    }
}

@Model final class OperationalCloudCheckpoint {
    @Attribute(.unique) var shopID: UUID
    var cloudUserID: String
    var token: Data?
    init(shopID: UUID, cloudUserID: String) {
        self.shopID = shopID; self.cloudUserID = cloudUserID
    }
}

@Model final class OperationalCloudMarker {
    @Attribute(.unique) var key: String
    var shopID: UUID
    var cloudUserID: String
    var payload: Data
    init(key: String, shopID: UUID, cloudUserID: String, payload: Data) {
        self.key = key; self.shopID = shopID
        self.cloudUserID = cloudUserID; self.payload = payload
    }
}

/// Uses an explicit compare-and-swap against the current server record, not a
/// last-writer-wins assignment. Incompatible offline edits stop synchronizing
/// that shop until a human resolves the conflict.
struct OperationalCloudAdapter {
    let bridge: CloudKitAdapter
    init(owner: UUID, shop: UUID) {
        bridge = CloudKitAdapter(owner: owner, shop: shop, namespace: "COVIOperations")
    }

    func page(after token: Data?) async throws -> (rows: [(String, Data)], token: Data, more: Bool) {
        var cursor: CKServerChangeToken?
        if let token {
            cursor = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token)
            guard cursor != nil else { throw SyncFault.invalidEvent }
        }
        let response = try await bridge.database.recordZoneChanges(
            inZoneWith: bridge.zone.zoneID, since: cursor, resultsLimit: 100)
        guard response.deletions.isEmpty else { throw SyncFault.journalChanged }
        let rows = try response.modificationResultsByID.map { id, result -> (String, Data) in
            let record = try result.get().record
            guard record.recordType == CloudKitSchemaContract.operational,
                  let bytes = record[CloudKitSchemaContract.payloadField] as? Data else {
                throw SyncFault.invalidEvent
            }
            return (id.recordName, bytes)
        }
        return (rows, try NSKeyedArchiver.archivedData(withRootObject: response.changeToken,
            requiringSecureCoding: true), response.moreComing)
    }

    func save(key: String, payload: Data, replacing expected: Data?) async throws {
        let id = CKRecord.ID(recordName: key, zoneID: bridge.zone.zoneID)
        let record: CKRecord
        do {
            let existing = try await bridge.database.record(for: id)
            guard let original = existing[CloudKitSchemaContract.payloadField] as? Data else {
                throw SyncFault.invalidEvent
            }
            if original == payload { return }
            guard original == expected else { throw SyncFault.journalChanged }
            record = existing
        } catch let error as CKError where error.code == .unknownItem {
            guard expected == nil else { throw SyncFault.journalChanged }
            record = CKRecord(recordType: CloudKitSchemaContract.operational, recordID: id)
        }
        record[CloudKitSchemaContract.payloadField] = payload as NSData
        do {
            let outcome = try await bridge.database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged,
                atomically: true)
            guard let result = outcome.saveResults[id] else { throw SyncFault.invalidEvent }
            _ = try result.get()
        } catch {
            let original = error
            guard let existing = try? await bridge.database.record(for: id),
                  existing[CloudKitSchemaContract.payloadField] as? Data == payload else { throw original }
        }
    }
}

@MainActor enum CloudOperationalSync {
    private static func make<T: Encodable>(_ value: T, kind: OperationalCloudRow.Kind,
                                           id: UUID, shop: Establishment) throws -> OperationalCloudRow {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return OperationalCloudRow(version: 1, ownerID: shop.ownerID, shopID: shop.id,
                                   kind: kind, entityID: id, state: try encoder.encode(value))
    }

    static func capture(shop: Establishment, context: ModelContext) throws -> [OperationalCloudRow] {
        let id = shop.id
        var rows: [OperationalCloudRow] = []
        for item in try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == id
        })) {
            rows.append(try make(OperationalCatalog(item), kind: .catalog, id: item.id, shop: shop))
        }
        for bale in try context.fetch(FetchDescriptor<Bale>(predicate: #Predicate { $0.shop == id })) {
            rows.append(try make(OperationalBale(bale), kind: .bale, id: bale.id, shop: shop))
        }
        for movement in try context.fetch(FetchDescriptor<StockMovement>(predicate: #Predicate {
            $0.establishmentID == id
        })) {
            rows.append(try make(OperationalStock(movement), kind: .stockMovement,
                                 id: movement.id, shop: shop))
        }
        for client in try context.fetch(FetchDescriptor<SalonClient>(predicate: #Predicate { $0.shop == id })) {
            rows.append(try make(OperationalClient(client), kind: .client, id: client.id, shop: shop))
        }
        for person in try context.fetch(FetchDescriptor<SalonStaff>(predicate: #Predicate { $0.shop == id })) {
            rows.append(try make(OperationalStaff(person), kind: .staff, id: person.id, shop: shop))
        }
        for visit in try context.fetch(FetchDescriptor<SalonVisit>(predicate: #Predicate { $0.shop == id })) {
            rows.append(try make(OperationalVisit(visit), kind: .visit, id: visit.id, shop: shop))
        }
        for table in try context.fetch(FetchDescriptor<DiningTable>(predicate: #Predicate {
            $0.establishmentID == id
        })) {
            rows.append(try make(OperationalTable(table), kind: .table, id: table.id, shop: shop))
        }
        let activeOrders = try context.fetch(FetchDescriptor<CommerceOrder>(predicate: #Predicate {
            $0.establishmentID == id && $0.stateRaw != "completed" && $0.stateRaw != "cancelled"
        }))
        for order in activeOrders {
            rows.append(try make(OperationalOrder(order), kind: .activeOrder,
                                 id: order.id, shop: shop))
            let oid = order.id
            for line in try context.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate {
                $0.orderID == oid
            })) {
                rows.append(try make(OperationalKitchenLine(line), kind: .kitchenLine,
                                     id: line.id, shop: shop))
            }
        }
        for sale in try context.fetch(FetchDescriptor<SalonSaleLine>(predicate: #Predicate { $0.shop == id })) {
            rows.append(try make(OperationalSalonSale(sale), kind: .salonSale,
                                 id: sale.id, shop: shop))
        }
        for membership in try context.fetch(FetchDescriptor<Membership>(predicate: #Predicate {
            $0.establishmentID == id
        })) where membership.role != .owner {
            rows.append(try make(OperationalMembership(membership), kind: .membership,
                                 id: membership.id, shop: shop))
        }
        return rows.sorted { ($0.kind.priority, $0.key) < ($1.kind.priority, $1.key) }
    }

    private static func decode<T: Decodable>(_ row: OperationalCloudRow, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: row.state)
    }

    private static func find<T: PersistentModel>(_ type: T.Type, id: UUID,
                                                  context: ModelContext) throws -> T? {
        // Typed queries keep imports linear rather than fetching an entire
        // inventory again for every incoming row.
        let key = ObjectIdentifier(type)
        if key == ObjectIdentifier(CatalogItem.self) {
            return try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
                $0.id == id
            })).first as? T
        }
        if key == ObjectIdentifier(Bale.self) {
            return try context.fetch(FetchDescriptor<Bale>(predicate: #Predicate { $0.id == id })).first as? T
        }
        if key == ObjectIdentifier(StockMovement.self) {
            return try context.fetch(FetchDescriptor<StockMovement>(predicate: #Predicate {
                $0.id == id
            })).first as? T
        }
        if key == ObjectIdentifier(SalonClient.self) {
            return try context.fetch(FetchDescriptor<SalonClient>(predicate: #Predicate { $0.id == id })).first as? T
        }
        if key == ObjectIdentifier(SalonStaff.self) {
            return try context.fetch(FetchDescriptor<SalonStaff>(predicate: #Predicate { $0.id == id })).first as? T
        }
        if key == ObjectIdentifier(SalonVisit.self) {
            return try context.fetch(FetchDescriptor<SalonVisit>(predicate: #Predicate { $0.id == id })).first as? T
        }
        if key == ObjectIdentifier(DiningTable.self) {
            return try context.fetch(FetchDescriptor<DiningTable>(predicate: #Predicate {
                $0.id == id
            })).first as? T
        }
        if key == ObjectIdentifier(CommerceOrder.self) {
            return try context.fetch(FetchDescriptor<CommerceOrder>(predicate: #Predicate {
                $0.id == id
            })).first as? T
        }
        if key == ObjectIdentifier(OrderLine.self) {
            return try context.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate { $0.id == id })).first as? T
        }
        if key == ObjectIdentifier(SalonSaleLine.self) {
            return try context.fetch(FetchDescriptor<SalonSaleLine>(predicate: #Predicate {
                $0.id == id
            })).first as? T
        }
        if key == ObjectIdentifier(Membership.self) {
            return try context.fetch(FetchDescriptor<Membership>(predicate: #Predicate { $0.id == id })).first as? T
        }
        throw SyncFault.invalidEvent
    }

    /// A completed receipt is already synchronized by the independently
    /// validated payment archive. Never restore an old open-table snapshot.
    private static func supersededByReceipt(_ row: OperationalCloudRow,
                                            context: ModelContext) throws -> Bool {
        switch row.kind {
        case .activeOrder:
            return try find(CommerceOrder.self, id: row.entityID, context: context)?.state == .completed
        case .kitchenLine:
            let detail = try decode(row, as: OperationalKitchenLine.self)
            return try find(CommerceOrder.self, id: detail.order, context: context)?.state == .completed
        case .table:
            let detail = try decode(row, as: OperationalTable.self)
            if let session = detail.session,
               try find(CommerceOrder.self, id: session, context: context)?.state == .completed { return true }
            if let released = detail.lastReleasedSession,
               let table = try find(DiningTable.self, id: detail.id, context: context),
               table.activeSessionID == released,
               let order = try find(CommerceOrder.self, id: released, context: context),
               order.establishmentID == detail.shop, order.tableID == detail.id,
               order.state == .completed, order.restaurantKeepsTable == true { return true }
            return false
        default: return false
        }
    }

    private static func hasPayment(orderID: UUID, context: ModelContext) throws -> Bool {
        var request = FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.orderID == orderID })
        request.fetchLimit = 1
        return try context.fetchCount(request) > 0
    }

    static func apply(_ row: OperationalCloudRow, shop: Establishment,
                      context: ModelContext) throws {
        try row.validate(shop: shop)
        let id = row.entityID, sid = shop.id
        switch row.kind {
        case .catalog:
            let x = try decode(row, as: OperationalCatalog.self)
            guard x.id == id, x.shop == sid, (2...120).contains(x.title.count),
                  x.price > 0, (0...100).contains(x.commission), x.reserved >= 0,
                  (x.menuCategory == nil || MenuGroup(rawValue: x.menuCategory!) != nil)
            else { throw SyncFault.invalidEvent }
            let item = try find(CatalogItem.self, id: id, context: context) ??
                CatalogItem(establishmentID: sid, title: x.title, priceMinor: x.price,
                            isService: x.service)
            guard item.establishmentID == sid, item.isService == x.service else { throw SyncFault.journalChanged }
            item.id = id
            item.title = x.title; item.priceMinor = x.price
            item.salonPercent = x.commission; item.menuCategory = x.menuCategory
            item.soldOut = x.unavailable; item.stockReserved = x.reserved; item.updatedAt = x.updated
            context.insert(item)
        case .bale:
            let x = try decode(row, as: OperationalBale.self)
            guard x.id == id, x.shop == sid, !x.label.isEmpty, x.cost >= 0 else { throw SyncFault.invalidEvent }
            if let prior = try find(Bale.self, id: id, context: context) {
                guard OperationalBale(prior) == x else { throw SyncFault.journalChanged }
            } else {
                let bale = Bale(shop: sid, label: x.label, cost: x.cost)
                bale.id = x.id; bale.received = x.received; context.insert(bale)
            }
        case .stockMovement:
            let x = try decode(row, as: OperationalStock.self)
            guard x.id == id, x.shop == sid, x.delta != 0, !x.reason.isEmpty else { throw SyncFault.invalidEvent }
            if let prior = try find(StockMovement.self, id: id, context: context) {
                guard OperationalStock(prior) == x else { throw SyncFault.journalChanged }
            } else {
                guard let item = try find(CatalogItem.self, id: x.item, context: context),
                      item.establishmentID == sid, !item.isService,
                      item.stockReserved >= 0 else { throw SyncFault.invalidEvent }
                let (next, overflow) = item.stockOnHand.addingReportingOverflow(x.delta)
                guard !overflow, next >= item.stockReserved, next >= 0 else { throw SyncFault.journalChanged }
                let log = StockMovement(establishmentID: sid, itemID: x.item,
                    delta: x.delta, reason: x.reason, actorID: x.actor)
                log.id = x.id; log.baleID = x.bale; log.createdAt = x.date
                context.insert(log); item.stockOnHand = next
            }
        case .client:
            let x = try decode(row, as: OperationalClient.self)
            guard x.id == id, x.shop == sid, (2...120).contains(x.name.count),
                  x.phone.count <= 30, x.notes.count <= 2_000, x.preferences.count <= 1_000
            else { throw SyncFault.invalidEvent }
            let client = try find(SalonClient.self, id: id, context: context) ??
                SalonClient(shop: sid, name: x.name)
            guard client.shop == sid else { throw SyncFault.journalChanged }
            client.id = id; client.name = x.name; client.phone = x.phone
            client.notes = x.notes; client.preferences = x.preferences; context.insert(client)
        case .staff:
            let x = try decode(row, as: OperationalStaff.self)
            guard x.id == id, x.shop == sid, (2...80).contains(x.name.count) else { throw SyncFault.invalidEvent }
            let person = try find(SalonStaff.self, id: id, context: context) ??
                SalonStaff(shop: sid, name: x.name)
            guard person.shop == sid else { throw SyncFault.journalChanged }
            person.id = id; person.name = x.name; person.active = x.active; context.insert(person)
        case .visit:
            let x = try decode(row, as: OperationalVisit.self)
            guard x.id == id, x.shop == sid, x.start < x.end,
                  x.end.timeIntervalSince(x.start) <= 720 * 60,
                  try find(SalonClient.self, id: x.client, context: context)?.shop == sid,
                  try find(CatalogItem.self, id: x.service, context: context)?.establishmentID == sid
            else { throw SyncFault.invalidEvent }
            let otherVisits = try context.fetch(FetchDescriptor<SalonVisit>(predicate: #Predicate { $0.shop == sid }))
            guard x.cancelled || otherVisits.allSatisfy({ prior in
                prior.id == id || prior.cancelled || prior.start >= x.end || prior.end <= x.start ||
                (prior.stylist != x.stylist && prior.client != x.client)
            }) else { throw SyncFault.journalChanged }
            let visit = try find(SalonVisit.self, id: id, context: context) ??
                SalonVisit(shop: sid, client: x.client, service: x.service,
                    stylist: x.stylist, start: x.start, end: x.end, walkIn: x.walkIn)
            guard visit.shop == sid else { throw SyncFault.journalChanged }
            visit.id = id; visit.client = x.client; visit.service = x.service
            visit.stylist = x.stylist; visit.start = x.start; visit.end = x.end
            visit.walkIn = x.walkIn; visit.cancelled = x.cancelled; visit.receipt = x.receipt
            context.insert(visit)
        case .activeOrder:
            let x = try decode(row, as: OperationalOrder.self)
            guard x.id == id, x.shop == sid, x.total >= 0, x.discount >= 0,
                  let state = OrderState(rawValue: x.state), state != .completed,
                  state != .cancelled else { throw SyncFault.invalidEvent }
            if let count = x.guestCount {
                guard shop.kind == .restaurant, x.table != nil, (1...100).contains(count)
                else { throw SyncFault.invalidEvent }
            }
            if try supersededByReceipt(row, context: context) { return }
            let order = try find(CommerceOrder.self, id: id, context: context) ??
                CommerceOrder(establishmentID: sid, createdByID: x.actor, tableID: x.table)
            guard order.establishmentID == sid else { throw SyncFault.journalChanged }
            if shop.kind == .restaurant, OperationalOrder(order) != x,
               try hasPayment(orderID: id, context: context) { throw SyncFault.journalChanged }
            order.id = id; order.tableID = x.table; order.customerID = x.customer
            order.restaurantGuestCount = x.guestCount ?? order.restaurantGuestCount
            order.createdByID = x.actor; order.createdAt = x.created
            order.stateRaw = x.state; order.totalMinor = x.total; order.discountMinor = x.discount
            context.insert(order)
        case .table:
            let x = try decode(row, as: OperationalTable.self)
            guard x.id == id, x.shop == sid, !x.label.isEmpty,
                  (1...100).contains(x.capacity), x.occupied == (x.session != nil),
                  (!x.billRequested || x.occupied) else { throw SyncFault.invalidEvent }
            let active = try x.session.flatMap { try find(CommerceOrder.self, id: $0, context: context) }
            if let active, active.establishmentID != sid || active.tableID != id { throw SyncFault.invalidEvent }
            let paidSession = active?.state == .completed
            let table = try find(DiningTable.self, id: id, context: context) ??
                DiningTable(establishmentID: sid, label: x.label, capacity: x.capacity)
            guard table.establishmentID == sid else { throw SyncFault.journalChanged }

            if let release = x.lastReleasedSession {
                guard shop.kind == .restaurant, release != x.session,
                      let releasedOrder = try find(CommerceOrder.self, id: release, context: context),
                      releasedOrder.establishmentID == sid, releasedOrder.tableID == id,
                      releasedOrder.state == .completed, releasedOrder.restaurantKeepsTable == true
                else { throw SyncFault.journalChanged }
                if !x.occupied, let current = table.activeSessionID, current != release { return }
                if let previous = table.lastReleasedSessionID, previous != release,
                   let previousOrder = try find(CommerceOrder.self, id: previous, context: context),
                   previousOrder.createdAt > releasedOrder.createdAt { return }
            }

            if paidSession, table.isOccupied, table.activeSessionID != x.session { return }
            if let active, paidSession, active.restaurantKeepsTable == true,
               let released = table.lastReleasedSessionID {
                let old = try find(CommerceOrder.self, id: released, context: context)
                if released == active.id || old.map({ $0.createdAt >= active.createdAt }) == true { return }
            }
            if let current = table.activeSessionID, current != x.session,
               let prior = try find(CommerceOrder.self, id: current, context: context),
               prior.state == .completed, prior.restaurantKeepsTable == true,
               x.lastReleasedSession != current { return }
            if let currentSession = table.activeSessionID, table.billRequested,
               currentSession != x.session || !x.billRequested,
               try find(CommerceOrder.self, id: currentSession, context: context)?.state != .completed,
               try hasPayment(orderID: currentSession, context: context) { throw SyncFault.journalChanged }

            let legacyPaid = paidSession && active?.restaurantKeepsTable != true
            table.id = id; table.label = x.label; table.capacity = x.capacity
            table.isOccupied = !legacyPaid && x.occupied
            table.activeSessionID = legacyPaid ? nil : x.session
            table.billRequested = !paidSession && x.billRequested
            table.lastReleasedSessionID = x.lastReleasedSession ?? table.lastReleasedSessionID
            context.insert(table)
        case .kitchenLine:
            let x = try decode(row, as: OperationalKitchenLine.self)
            guard x.id == id, x.quantity > 0, x.price > 0,
                  x.preparation == nil || (x.preparation != Prep.received.rawValue && Prep(rawValue: x.preparation!) != nil),
                  x.awaitingClaim != true || (shop.kind == .restaurant && x.preparation == Prep.cooking.rawValue),
                  try find(CommerceOrder.self, id: x.order, context: context)?.establishmentID == sid
            else { throw SyncFault.invalidEvent }
            if try supersededByReceipt(row, context: context) { return }
            let line = try find(OrderLine.self, id: id, context: context) ??
                OrderLine(orderID: x.order, catalogItemID: x.item,
                          quantity: x.quantity, unitPriceMinor: x.price)
            guard line.orderID == x.order else { throw SyncFault.journalChanged }
            if x.awaitingClaim == true, let state = line.preparation.flatMap(Prep.init(rawValue:)),
               state != .received { return }
            if shop.kind == .restaurant, OperationalKitchenLine(line) != x,
               try hasPayment(orderID: x.order, context: context) { throw SyncFault.journalChanged }
            line.id = id; line.catalogItemID = x.item; line.quantity = x.quantity
            line.unitPriceMinor = x.price; line.dishName = x.name
            line.preparation = x.localPreparation; line.sentAt = x.sentAt; context.insert(line)
        case .salonSale:
            let x = try decode(row, as: OperationalSalonSale.self)
            guard (0...100).contains(x.percent) else { throw SyncFault.invalidEvent }
            let rate = Int64(x.percent)
            let expectedCommission = (x.gross / 100) * rate + ((x.gross % 100) * rate) / 100
            guard x.id == id, x.shop == sid, x.units > 0, x.gross > 0,
                  (0...100).contains(x.percent), x.commission >= 0, x.commission <= x.gross,
                  x.commission == expectedCommission,
                  try find(CommerceOrder.self, id: x.order, context: context)?.state == .completed
            else { throw SyncFault.invalidEvent }
            if let prior = try find(SalonSaleLine.self, id: id, context: context) {
                guard OperationalSalonSale(prior) == x else { throw SyncFault.journalChanged }
            } else {
                context.insert(SalonSaleLine(id: id, shop: sid, order: x.order,
                    client: x.client, stylist: x.stylist, title: x.title, service: x.service,
                    units: x.units, gross: x.gross, percent: x.percent,
                    commission: x.commission, date: x.date))
            }
        case .membership:
            let x = try decode(row, as: OperationalMembership.self)
            guard x.id == id, x.shop == sid, StaffRole(rawValue: x.role) != nil,
                  (x.role != StaffRole.owner.rawValue || x.account == shop.ownerID)
            else { throw SyncFault.invalidEvent }
            let member = try find(Membership.self, id: id, context: context) ??
                Membership(accountID: x.account, establishmentID: sid,
                           role: StaffRole(rawValue: x.role) ?? .cashier)
            guard member.establishmentID == sid, member.accountID == x.account else {
                throw SyncFault.journalChanged
            }
            member.id = id; member.roleRaw = x.role; member.active = x.active; context.insert(member)
        }
    }

    /// Merge never replaces unsynchronized local edits. A diverged entity is a
    /// conflict, not an invitation to pick the most recent device clock.
    static func merge(_ downloaded: [(String, Data)], shop: Establishment,
                      cloudUserID: String, context: ModelContext) throws {
        let sid = shop.id
        let existingMarkers = try context.fetch(FetchDescriptor<OperationalCloudMarker>(predicate: #Predicate {
            $0.shopID == sid
        }))
        guard existingMarkers.allSatisfy({ $0.cloudUserID == cloudUserID }) else {
            throw SyncFault.accountChanged
        }
        var markers = Dictionary(uniqueKeysWithValues: existingMarkers.map { ($0.key, $0) })
        var current = Dictionary(uniqueKeysWithValues: try capture(shop: shop, context: context)
            .map { ($0.key, $0) })

        let rows = try downloaded.map { name, bytes -> (OperationalCloudRow, Data, Int) in
            let row = try JSONDecoder().decode(OperationalCloudRow.self, from: bytes)
            try row.validate(shop: shop)
            guard row.key == name, try row.bytes() == bytes else { throw SyncFault.invalidEvent }
            let stockOrder: Int
            if row.kind == .stockMovement {
                stockOrder = try decode(row, as: OperationalStock.self).delta > 0 ? 0 : 1
            } else { stockOrder = 0 }
            return (row, bytes, stockOrder)
        }.sorted { a, b in
            (a.0.kind.priority, a.2, a.0.key) < (b.0.kind.priority, b.2, b.0.key)
        }
        guard Set(rows.map { $0.0.key }).count == rows.count else { throw SyncFault.journalChanged }

        for (row, bytes, _) in rows {
            let key = row.key
            let oldPayload = markers[key]?.payload
            let localPayload = try current[key]?.bytes()
            let protectedByReceipt = try supersededByReceipt(row, context: context)
            if let oldPayload {
                if oldPayload != bytes {
                    guard !row.kind.immutable else { throw SyncFault.journalChanged }
                    guard localPayload != nil || protectedByReceipt else {
                        throw SyncFault.journalChanged
                    }
                    guard localPayload == oldPayload || localPayload == bytes ||
                          protectedByReceipt else {
                        throw SyncFault.journalChanged
                    }
                }
            } else if let localPayload, localPayload != bytes,
                      !protectedByReceipt {
                throw SyncFault.journalChanged
            }
            if oldPayload != bytes && localPayload != bytes &&
               (!protectedByReceipt || row.kind == .table) {
                try apply(row, shop: shop, context: context)
            }
            if let marker = markers[key] {
                marker.payload = bytes
            } else {
                let marker = OperationalCloudMarker(key: key, shopID: sid,
                    cloudUserID: cloudUserID, payload: bytes)
                context.insert(marker); markers[key] = marker
            }
            current[key] = row
        }
    }

    /// Existing stock must be auditable as an exact sum of immutable movements.
    /// Never fabricate stock on another device from a mutable product counter.
    static func validateStock(shop: Establishment, context: ModelContext) throws {
        let sid = shop.id
        let articles = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == sid
        }))
        let movements = try context.fetch(FetchDescriptor<StockMovement>(predicate: #Predicate {
            $0.establishmentID == sid
        }))
        var totals: [UUID: Int] = [:]
        for movement in movements {
            guard movement.delta != 0,
                  let item = articles.first(where: { $0.id == movement.itemID && !$0.isService }) else {
                throw SyncFault.journalChanged
            }
            let (sum, overflow) = (totals[item.id] ?? 0).addingReportingOverflow(movement.delta)
            guard !overflow else { throw SyncFault.journalChanged }
            totals[item.id] = sum
        }
        for item in articles where !item.isService {
            guard item.stockOnHand == (totals[item.id] ?? 0),
                  item.stockReserved >= 0, item.stockOnHand >= item.stockReserved else {
                throw SyncFault.journalChanged
            }
        }
    }

    static func cycle(shop: Establishment, context: ModelContext) async throws {
        guard !shop.archived else { return }
        let cloud = OperationalCloudAdapter(owner: shop.ownerID, shop: shop.id)
        let identity = try await cloud.bridge.container.userRecordID().recordName
        try Task.checkCancellation()
        let sid = shop.id
        let checkpoints = try context.fetch(FetchDescriptor<OperationalCloudCheckpoint>(predicate: #Predicate {
            $0.shopID == sid
        }))
        let checkpoint = checkpoints.first ?? OperationalCloudCheckpoint(
            shopID: sid, cloudUserID: identity)
        guard checkpoint.cloudUserID == identity else { throw SyncFault.accountChanged }
        if checkpoints.isEmpty { context.insert(checkpoint); try context.save() }
        try await cloud.bridge.prepare()

        // Download a complete change batch before committing the change token.
        // Catalogs and clients are applied before inventory and reservations.
        var changes: [(String, Data)] = []
        var lastToken = checkpoint.token
        while true {
            try Task.checkCancellation()
            do {
                let page = try await cloud.page(after: lastToken)
                changes.append(contentsOf: page.rows)
                lastToken = page.token
                if !page.more { break }
            } catch let error as CKError where error.code == .changeTokenExpired && lastToken != nil {
                changes.removeAll()
                lastToken = nil
            }
        }
        try Task.checkCancellation()
        do {
            try merge(changes, shop: shop, cloudUserID: identity, context: context)
            try validateStock(shop: shop, context: context)
            checkpoint.token = lastToken
            try context.save()
        } catch { context.rollback(); throw error }

        let markers = try context.fetch(FetchDescriptor<OperationalCloudMarker>(predicate: #Predicate {
            $0.shopID == sid
        }))
        guard markers.allSatisfy({ $0.cloudUserID == identity }) else { throw SyncFault.accountChanged }
        var byKey = Dictionary(uniqueKeysWithValues: markers.map { ($0.key, $0) })
        for row in try capture(shop: shop, context: context) {
            try Task.checkCancellation()
            let bytes = try row.bytes()
            let marker = byKey[row.key]
            guard marker?.payload != bytes else { continue }
            guard marker == nil || !row.kind.immutable else { throw SyncFault.journalChanged }
            try await cloud.save(key: row.key, payload: bytes, replacing: marker?.payload)
            try Task.checkCancellation()
            if let marker { marker.payload = bytes }
            else {
                let newMarker = OperationalCloudMarker(key: row.key, shopID: sid,
                    cloudUserID: identity, payload: bytes)
                context.insert(newMarker); byKey[row.key] = newMarker
            }
            try context.save()
        }
    }
}
