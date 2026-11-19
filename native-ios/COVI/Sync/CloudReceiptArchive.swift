import CloudKit
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
        let id = orderID
        if let existing = try context.fetch(FetchDescriptor<CommerceOrder>(
            predicate: #Predicate { $0.id == id })).first {
            guard existing.establishmentID == shop.id, existing.state == .completed,
                  existing.totalMinor == totalMinor, existing.discountMinor == discountMinor
            else { throw SyncFault.journalChanged }
            let localLines = try context.fetch(FetchDescriptor<OrderLine>(
                predicate: #Predicate { $0.orderID == id }))
            let localPayments = try context.fetch(FetchDescriptor<PaymentRecord>(
                predicate: #Predicate { $0.orderID == id }))
            guard localLines.count == articles.count, localPayments.count == confirmations.count else {
                throw SyncFault.journalChanged
            }
            for article in articles {
                guard let local = localLines.first(where: { $0.id == article.id }),
                      local.catalogItemID == article.catalogItemID,
                      local.quantity == article.quantity,
                      local.unitPriceMinor == article.unitPriceMinor else {
                    throw SyncFault.journalChanged
                }
            }
            for confirmation in confirmations {
                guard let local = localPayments.first(where: { $0.id == confirmation.id }),
                      local.method == confirmation.method,
                      local.amountMinor == confirmation.amountMinor,
                      local.confirmedByID == confirmation.confirmedByID else {
                    throw SyncFault.journalChanged
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
