import SwiftUI
import SwiftData

struct ReceiptDetail: View {
    let order: CommerceOrder
    let shop: Establishment
    @Query private var lines: [OrderLine]
    @Query private var payments: [PaymentRecord]
    @Query private var items: [CatalogItem]
    private var receipt: Result<ReceiptSummary, Error> {
        Result { try ReceiptBuilder.create(order: order, shop: shop, lines: lines,
                                          products: items, payments: payments) }
    }

    init(order: CommerceOrder, shop: Establishment) {
        self.order = order
        self.shop = shop
        let orderID = order.id, shopID = shop.id
        _lines = Query(filter: #Predicate<OrderLine> { $0.orderID == orderID })
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.orderID == orderID })
        _items = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == shopID })
    }

    var body: some View {
        Group {
            switch receipt {
            case .failure(let error):
                ContentUnavailableView("Reçu indisponible", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            case .success(let model):
                List {
                    Section {
                        Text(shop.name).font(.title2.bold())
                        Text(shop.city).foregroundStyle(.secondary)
                        LabeledContent("Commande", value: String(order.id.uuidString.prefix(8)))
                        LabeledContent("Date", value: order.createdAt.formatted(date: .abbreviated,
                                                                               time: .shortened))
                    }
                    Section("Détail des articles") {
                        ForEach(model.lines) { line in
                            LabeledContent("\(line.quantity) × \(line.name)",
                                           value: "\(line.amountMinor) \(model.currencyCode)")
                        }
                    }
                    Section("Total confirmé") {
                        LabeledContent("Sous-total", value: "\(model.subtotalMinor) \(model.currencyCode)")
                        if model.discountMinor > 0 {
                            LabeledContent("Remise", value: "−\(model.discountMinor) \(model.currencyCode)")
                        }
                        LabeledContent("À payer", value: "\(model.totalMinor) \(model.currencyCode)")
                            .font(.headline)
                        LabeledContent("Règlement", value: model.method)
                        LabeledContent("Confirmé le", value: model.confirmedAt.formatted(date: .abbreviated,
                                                                                        time: .shortened))
                    }
                    Section {
                        ShareLink(item: model.shareText) {
                            Label("Partager le reçu", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .scrollContentBackground(.hidden).background(COVITheme.cream)
            }
        }
        .navigationTitle("Reçu")
    }
}
