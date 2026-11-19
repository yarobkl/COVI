import CloudKit
import CryptoKit
import Foundation
import SwiftData

/// Un reçu confirmé est immuable. Les stocks restent locaux tant qu'un journal
/// de mouvements fusionnable n'est pas prêt : ne jamais les écraser à distance.
struct ArchivedReceipt: Codable, Equatable {
    struct Article: Codable, Equatable {
        let id: UUID
        let catalogItemID: UUID
        let name: String
        let quantity: Int
        let unitPriceMinor: Int64
    }
    struct Confirmation: Codable, Equatable {
        let id: UUID
        let method: String
        let amountMinor: Int64
        let confirmedByID: UUID
        let confirmedAt: Date
        let cashReceived: Int64?
    }

    let version: Int
    let ownerID: UUID
    let establishmentID: UUID
    let orderID: UUID
    let tableID: UUID?
    let customerID: UUID?
    let createdByID: UUID
    let createdAt: Date
    let totalMinor: Int64
    let discountMinor: Int64
    let articles: [Article]
    let confirmations: [Confirmation]

    @MainActor
    init(shop: Establishment, order: CommerceOrder, lines: [OrderLine],
         payments: [PaymentRecord], catalog: [CatalogItem]) throws {
        _ = try ReceiptBuilder.create(order: order, shop: shop, lines: lines,
                                      products: catalog, payments: payments)
        version = 1
        ownerID = shop.ownerID
        establishmentID = shop.id
        orderID = order.id
        tableID = order.tableID
        customerID = order.customerID
        createdByID = order.createdByID
        createdAt = order.createdAt
        totalMinor = order.totalMinor
        discountMinor = order.discountMinor
        articles = lines.filter { $0.orderID == order.id }.map { line in
            Article(id: line.id, catalogItemID: line.catalogItemID,
                    name: line.dishName ?? catalog.first(where: { $0.id == line.catalogItemID })?.title ?? "Article",
                    quantity: line.quantity, unitPriceMinor: line.unitPriceMinor)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        confirmations = payments.filter { $0.orderID == order.id && $0.establishmentID == shop.id }.map {
            Confirmation(id: $0.id, method: $0.method, amountMinor: $0.amountMinor,
                         confirmedByID: $0.confirmedByID, confirmedAt: $0.confirmedAt,
                         cashReceived: $0.cashReceived)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    @MainActor
    func importIfNeeded(shop: Establishment, context: ModelContext) throws {
        guard version == 1, establishmentID == shop.id, ownerID == shop.ownerID,
              !articles.isEmpty, !confirmations.isEmpty else { throw SyncFault.invalidEvent }
        let verifier = CommerceOrder(establishmentID: shop.id, createdByID: createdByID, tableID: tableID)
        verifier.id = orderID; verifier.customerID = customerID; verifier.createdAt = createdAt
        verifier.state = .completed; verifier.totalMinor = totalMinor; verifier.discountMinor = discountMinor
        let verifierLines = articles.map { article -> OrderLine in
            let line = OrderLine(orderID: orderID, catalogItemID: article.catalogItemID,
                quantity: article.quantity, unitPriceMinor: article.unitPriceMinor)
            line.id = article.id; line.dishName = article.name
            return line
        }
        let verifierPayments = confirmations.map { confirmation -> PaymentRecord in
            let payment = PaymentRecord(orderID: orderID, establishmentID: shop.id,
                method: confirmation.method, amountMinor: confirmation.amountMinor,
                confirmedByID: confirmation.confirmedByID)
            payment.id = confirmation.id; payment.confirmedAt = confirmation.confirmedAt
            payment.cashReceived = confirmation.cashReceived
            return payment
        }
        guard Set(articles.map(\.id)).count == articles.count,
              Set(confirmations.map(\.id)).count == confirmations.count else { throw SyncFault.invalidEvent }
        do {
            _ = try ReceiptBuilder.create(order: verifier, shop: shop, lines: verifierLines,
                                          products: [], payments: verifierPayments)
        } catch { throw SyncFault.invalidEvent }
        let id = orderID
        if let existing = try context.fetch(FetchDescriptor<CommerceOrder>(
            predicate: #Predicate { $0.id == id })).first {
            guard existing.establishmentID == shop.id,
                  existing.tableID == tableID, existing.customerID == customerID,
                  existing.createdByID == createdByID,
                  abs(existing.createdAt.timeIntervalSince(createdAt)) < 1
            else { throw SyncFault.journalChanged }
            let localLines = try context.fetch(FetchDescriptor<OrderLine>(
                predicate: #Predicate { $0.orderID == id }))
            let localPayments = try context.fetch(FetchDescriptor<PaymentRecord>(
                predicate: #Predicate { $0.orderID == id }))
            guard localLines.count <= articles.count, localPayments.count <= confirmations.count else {
                throw SyncFault.journalChanged
            }
            for local in localLines {
                guard let article = articles.first(where: { $0.id == local.id }),
                      local.catalogItemID == article.catalogItemID,
                      local.quantity == article.quantity,
                      local.unitPriceMinor == article.unitPriceMinor,
                      local.dishName == article.name else {
                    throw SyncFault.journalChanged
                }
            }
            for local in localPayments {
                guard let confirmation = confirmations.first(where: { $0.id == local.id }),
                      local.method == confirmation.method,
                      local.amountMinor == confirmation.amountMinor,
                      local.confirmedByID == confirmation.confirmedByID,
                      local.cashReceived == confirmation.cashReceived,
                      abs(local.confirmedAt.timeIntervalSince(confirmation.confirmedAt)) < 1 else {
                    throw SyncFault.journalChanged
                }
            }
            if existing.state == .completed {
                guard existing.totalMinor == totalMinor,
                      existing.discountMinor == discountMinor,
                      localLines.count == articles.count,
                      localPayments.count == confirmations.count else { throw SyncFault.journalChanged }
                return
            }
            guard existing.state == .accepted || existing.state == .served ||
                  existing.state == .ready || existing.state == .preparing,
                  localPayments.isEmpty else { throw SyncFault.journalChanged }

            // An open restaurant order can have been mirrored before its
            // payment. Only a verified receipt is allowed to close it.
            for article in articles where !localLines.contains(where: { $0.id == article.id }) {
                let line = OrderLine(orderID: id, catalogItemID: article.catalogItemID,
                    quantity: article.quantity, unitPriceMinor: article.unitPriceMinor)
                line.id = article.id; line.dishName = article.name
                context.insert(line)
            }
            for confirmation in confirmations {
                let payment = PaymentRecord(orderID: id, establishmentID: shop.id,
                    method: confirmation.method, amountMinor: confirmation.amountMinor,
                    confirmedByID: confirmation.confirmedByID)
                payment.id = confirmation.id; payment.confirmedAt = confirmation.confirmedAt
                payment.cashReceived = confirmation.cashReceived
                context.insert(payment)
            }
            existing.totalMinor = totalMinor
            existing.discountMinor = discountMinor
            existing.state = .completed
            if let tableID {
                let tables = try context.fetch(FetchDescriptor<DiningTable>(predicate: #Predicate {
                    $0.id == tableID
                }))
                if let table = tables.first, table.activeSessionID == id {
                    table.activeSessionID = nil; table.isOccupied = false
                    table.billRequested = false
                }
            }
            return
        }

        let order = CommerceOrder(establishmentID: shop.id, createdByID: createdByID, tableID: tableID)
        order.id = orderID
        order.customerID = customerID
        order.createdAt = createdAt
        order.totalMinor = totalMinor
        order.discountMinor = discountMinor
        order.state = .completed
        let rows = articles.map { article -> OrderLine in
            let line = OrderLine(orderID: orderID, catalogItemID: article.catalogItemID,
                                 quantity: article.quantity, unitPriceMinor: article.unitPriceMinor)
            line.id = article.id
            line.dishName = article.name
            return line
        }
        let paid = confirmations.map { confirmation -> PaymentRecord in
            let payment = PaymentRecord(orderID: orderID, establishmentID: shop.id, method: confirmation.method,
                                        amountMinor: confirmation.amountMinor,
                                        confirmedByID: confirmation.confirmedByID)
            payment.id = confirmation.id
            payment.confirmedAt = confirmation.confirmedAt
            payment.cashReceived = confirmation.cashReceived
            return payment
        }
        do {
            _ = try ReceiptBuilder.create(order: order, shop: shop, lines: rows,
                                          products: [], payments: paid)
        } catch { throw SyncFault.invalidEvent }

        context.insert(order)
        for line in rows { context.insert(line) }
        for payment in paid { context.insert(payment) }
    }
}

@Model final class ReceiptCloudCheckpoint {
    @Attribute(.unique) var shopID: UUID
    var cloudUserID: String
    var token: Data?
    init(shopID: UUID, cloudUserID: String) {
        self.shopID = shopID
        self.cloudUserID = cloudUserID
    }
}

@Model final class ReceiptCloudMarker {
    @Attribute(.unique) var orderID: UUID
    var shopID: UUID
    var cloudUserID: String
    init(orderID: UUID, shopID: UUID, cloudUserID: String) {
        self.orderID = orderID
        self.shopID = shopID
        self.cloudUserID = cloudUserID
    }
}

@MainActor enum CloudReceiptArchive {
    static func cycle(shop: Establishment, context: ModelContext) async throws {
        let cloud = CloudKitAdapter(owner: shop.ownerID, shop: shop.id, namespace: "COVIReceipts")
        let cloudID = try await cloud.container.userRecordID().recordName
        let shopID = shop.id
        let checkpoints = try context.fetch(FetchDescriptor<ReceiptCloudCheckpoint>(
            predicate: #Predicate { $0.shopID == shopID }))
        let checkpoint = checkpoints.first ?? ReceiptCloudCheckpoint(shopID: shopID, cloudUserID: cloudID)
        guard checkpoint.cloudUserID == cloudID else { throw SyncFault.accountChanged }
        if checkpoints.isEmpty { context.insert(checkpoint); try context.save() }

        try await cloud.prepare()
        let completed = OrderState.completed.rawValue
        let orders = try context.fetch(FetchDescriptor<CommerceOrder>(
            predicate: #Predicate { $0.establishmentID == shopID && $0.stateRaw == completed }))
        let products = try context.fetch(FetchDescriptor<CatalogItem>(
            predicate: #Predicate { $0.establishmentID == shopID }))
        let savedMarkers = try context.fetch(FetchDescriptor<ReceiptCloudMarker>(
            predicate: #Predicate { $0.shopID == shopID }))
        var alreadySynced = Set(savedMarkers.map(\.orderID))

        for order in orders where order.totalMinor > 0 && !alreadySynced.contains(order.id) {
            try Task.checkCancellation()
            let orderID = order.id
            let rows = try context.fetch(FetchDescriptor<OrderLine>(
                predicate: #Predicate { $0.orderID == orderID }))
            let paid = try context.fetch(FetchDescriptor<PaymentRecord>(
                predicate: #Predicate { $0.orderID == orderID }))
            let archive: ArchivedReceipt
            do {
                archive = try ArchivedReceipt(shop: shop, order: order, lines: rows,
                                              payments: paid, catalog: products)
            } catch ReceiptBuilder.Fault.noPayment {
                continue
            }
            let bytes = try JSONEncoder().encode(archive)
            try await cloud.push(id: orderID, bytes: bytes)
            try Task.checkCancellation()
            context.insert(ReceiptCloudMarker(orderID: orderID, shopID: shopID, cloudUserID: cloudID))
            try context.save()
            alreadySynced.insert(orderID)
        }

        while true {
            try Task.checkCancellation()
            do {
                let page = try await cloud.page(after: checkpoint.token)
                try Task.checkCancellation()
                do {
                    for (key, bytes) in page.events {
                        let archive = try JSONDecoder().decode(ArchivedReceipt.self, from: bytes)
                        guard archive.orderID == key else { throw SyncFault.invalidEvent }
                        try archive.importIfNeeded(shop: shop, context: context)
                        if !alreadySynced.contains(key) {
                            context.insert(ReceiptCloudMarker(orderID: key, shopID: shopID,
                                                              cloudUserID: cloudID))
                            alreadySynced.insert(key)
                        }
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
}

/// Les dépenses sont répliquées comme deux faits immuables : saisie et éventuelle
/// annulation. Le stockage iCloud privé ne confirme jamais un paiement client.
struct CloudExpenseFact: Codable, Equatable {
    enum Action: String, Codable { case created, voided }
    let version: Int
    let action: Action
    let ownerID: UUID
    let shopID: UUID
    let expenseID: UUID
    let actorID: UUID
    let category: String
    let amountMinor: Int64
    let spentAt: Date
    let note: String
    let voidedAt: Date?
    let voidedByID: UUID?

    init(shop: Establishment, entry: ExpenseEntry, action: Action) {
        version = 1
        self.action = action
        ownerID = shop.ownerID
        shopID = shop.id
        expenseID = entry.id
        actorID = entry.actorID
        category = entry.category
        amountMinor = entry.amountMinor
        spentAt = entry.spentAt
        note = entry.note
        voidedAt = action == .voided ? entry.voidedAt : nil
        voidedByID = action == .voided ? entry.voidedByID : nil
    }

    static func eventID(for expenseID: UUID, action: Action) -> UUID {
        guard action == .voided else { return expenseID }
        var bytes = Array(SHA256.hash(data: Data("COVI.expense.void.v1.\(expenseID.uuidString)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    func validate(shop: Establishment) throws {
        guard version == 1, shopID == shop.id, ownerID == shop.ownerID,
              amountMinor > 0, ExpenseCategory.all.contains(category)
        else { throw SyncFault.invalidEvent }
        switch action {
        case .created:
            guard voidedAt == nil, voidedByID == nil else { throw SyncFault.invalidEvent }
        case .voided:
            guard voidedAt != nil, voidedByID == ownerID
            else { throw SyncFault.invalidEvent }
        }
    }

    @MainActor
    func apply(shop: Establishment, context: ModelContext) throws {
        try validate(shop: shop)
        let id = expenseID
        let stored = try context.fetch(FetchDescriptor<ExpenseEntry>(predicate: #Predicate { $0.id == id })).first
        if let stored {
            guard stored.establishmentID == shop.id, stored.actorID == actorID,
                  stored.category == category, stored.amountMinor == amountMinor,
                  abs(stored.spentAt.timeIntervalSince(spentAt)) < 1,
                  stored.note == note else { throw SyncFault.journalChanged }
            if action == .voided {
                if let existing = stored.voidedAt {
                    guard let voidedAt, abs(existing.timeIntervalSince(voidedAt)) < 1,
                          stored.voidedByID == voidedByID else { throw SyncFault.journalChanged }
                } else {
                    stored.voidedAt = voidedAt
                    stored.voidedByID = voidedByID
                }
            }
        } else if action == .created {
            let entry = ExpenseEntry(establishmentID: shop.id, actorID: actorID, category: category,
                                     amountMinor: amountMinor, spentAt: spentAt, note: note)
            entry.id = expenseID
            context.insert(entry)
        } else {
            // Le changement CloudKit peut arriver avant la saisie d'origine.
            let key = Self.eventID(for: expenseID, action: .voided)
            let pending = try context.fetch(FetchDescriptor<PendingExpenseVoid>(predicate: #Predicate {
                $0.eventID == key
            }))
            if let existing = pending.first {
                guard try JSONDecoder().decode(CloudExpenseFact.self, from: existing.payload) == self
                else { throw SyncFault.journalChanged }
            } else {
                context.insert(PendingExpenseVoid(eventID: key, shopID: shop.id,
                    payload: try canonicalData()))
            }
        }
    }
}

@Model final class ExpenseCloudCheckpoint {
    @Attribute(.unique) var shopID: UUID
    var cloudUserID: String
    var token: Data?
    init(shopID: UUID, cloudUserID: String) {
        self.shopID = shopID; self.cloudUserID = cloudUserID
    }
}

@Model final class ExpenseCloudMarker {
    @Attribute(.unique) var eventID: UUID
    var shopID: UUID
    var cloudUserID: String
    init(eventID: UUID, shopID: UUID, cloudUserID: String) {
        self.eventID = eventID; self.shopID = shopID; self.cloudUserID = cloudUserID
    }
}

@Model final class PendingExpenseVoid {
    @Attribute(.unique) var eventID: UUID
    var shopID: UUID
    var payload: Data
    init(eventID: UUID, shopID: UUID, payload: Data) {
        self.eventID = eventID; self.shopID = shopID; self.payload = payload
    }
}

@MainActor enum CloudExpenseLedger {
    static func resolvePending(shop: Establishment, context: ModelContext) throws {
        let shopID = shop.id
        let rows = try context.fetch(FetchDescriptor<PendingExpenseVoid>(predicate: #Predicate {
            $0.shopID == shopID
        }))
        for row in rows {
            let fact = try JSONDecoder().decode(CloudExpenseFact.self, from: row.payload)
            try fact.validate(shop: shop)
            guard fact.action == .voided,
                  CloudExpenseFact.eventID(for: fact.expenseID, action: .voided) == row.eventID
            else { throw SyncFault.invalidEvent }
            let id = fact.expenseID
            if try context.fetchCount(FetchDescriptor<ExpenseEntry>(predicate: #Predicate { $0.id == id })) > 0 {
                try fact.apply(shop: shop, context: context)
                context.delete(row)
            }
        }
    }

    static func cycle(shop: Establishment, context: ModelContext) async throws {
        let cloud = CloudKitAdapter(owner: shop.ownerID, shop: shop.id, namespace: "COVIExpenses")
        let identity = try await cloud.container.userRecordID().recordName
        let shopID = shop.id
        let checkpoints = try context.fetch(FetchDescriptor<ExpenseCloudCheckpoint>(predicate: #Predicate {
            $0.shopID == shopID
        }))
        let checkpoint = checkpoints.first ?? ExpenseCloudCheckpoint(shopID: shopID, cloudUserID: identity)
        guard checkpoint.cloudUserID == identity else { throw SyncFault.accountChanged }
        if checkpoints.isEmpty { context.insert(checkpoint); try context.save() }
        try await cloud.prepare()
        let entries = try context.fetch(FetchDescriptor<ExpenseEntry>(predicate: #Predicate {
            $0.establishmentID == shopID
        }))
        let markers = try context.fetch(FetchDescriptor<ExpenseCloudMarker>(predicate: #Predicate {
            $0.shopID == shopID
        }))
        guard markers.allSatisfy({ $0.cloudUserID == identity }) else { throw SyncFault.accountChanged }
        var uploaded = Set(markers.map(\.eventID))

        for entry in entries {
            try Task.checkCancellation()
            let actions: [CloudExpenseFact.Action] = entry.voidedAt == nil ? [.created] : [.created, .voided]
            for action in actions {
                let fact = CloudExpenseFact(shop: shop, entry: entry, action: action)
                try fact.validate(shop: shop)
                let key = CloudExpenseFact.eventID(for: entry.id, action: action)
                guard !uploaded.contains(key) else { continue }
                try await cloud.push(id: key, bytes: try fact.canonicalData())
                try Task.checkCancellation()
                context.insert(ExpenseCloudMarker(eventID: key, shopID: shop.id, cloudUserID: identity))
                try context.save()
                uploaded.insert(key)
            }
        }

        while true {
            try Task.checkCancellation()
            do {
                let page = try await cloud.page(after: checkpoint.token)
                do {
                    for (key, bytes) in page.events {
                        let fact = try JSONDecoder().decode(CloudExpenseFact.self, from: bytes)
                        guard CloudExpenseFact.eventID(for: fact.expenseID, action: fact.action) == key
                        else { throw SyncFault.invalidEvent }
                        try fact.apply(shop: shop, context: context)
                        if !uploaded.contains(key) {
                            context.insert(ExpenseCloudMarker(eventID: key, shopID: shop.id,
                                                              cloudUserID: identity))
                            uploaded.insert(key)
                        }
                    }
                    try resolvePending(shop: shop, context: context)
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
}
