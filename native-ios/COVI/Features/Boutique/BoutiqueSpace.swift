import SwiftUI
import SwiftData

@MainActor
struct BoutiqueSpace: View {
    let tab: BusinessTab
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    let startSale: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var goods: [CatalogItem]
    @Query private var sales: [CommerceOrder]
    @State private var search = ""
    @State private var basket: [UUID: Int] = [:]
    @State private var discount = ""
    @State private var quote: Quote?
    @State private var message = ""
    struct Quote: Identifiable { let id = UUID(); let due: Int64 }
    init(tab: BusinessTab, shop: Establishment, actor: UUID, pin: PINManager, startSale: @escaping () -> Void) {
        self.tab = tab; self.shop = shop; self.actor = actor; self.pin = pin; self.startSale = startSale
        let id = shop.id
        _goods = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id && !$0.isService }, sort: \.title)
        _sales = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id }, sort: \.createdAt, order: .reverse)
    }
    var lines: [BoutiqueLedger.Line] {
        goods.compactMap { item in basket[item.id].map { BoutiqueLedger.Line(product: item, units: $0) } }
    }
    var rebate: Int64 { discount.isEmpty ? 0 : Int64(discount) ?? -1 }
    var total: Int64? { try? BoutiqueLedger.total(lines, discount: rebate) }
    var filtered: [CatalogItem] { goods.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if tab == .home {
                let today = sales.filter { $0.state == .completed && Calendar.current.isDateInToday($0.createdAt) }
                Section("Ventes du jour") {
                    Text("\(today.reduce(Decimal.zero) { $0 + Decimal($1.totalMinor) }.formatted()) FCFA").font(.title.bold())
                    Text("\(today.count) ventes")
                    COVIButton("Vendre") { startSale() }
                }
                Section("À suivre") { Text("\(goods.filter { $0.stockOnHand - $0.stockReserved <= 2 }.count) articles à stock faible") }
                Section("Dernières ventes") {
                    ForEach(sales.filter { $0.state == .completed }.prefix(5)) { sale in
                        LabeledContent(sale.createdAt.formatted(date: .abbreviated, time: .shortened), value: "\(sale.totalMinor) FCFA")
                    }
                }
            } else {
                if tab == .stock {
                    NavigationLink("Arrivages de balles") { BaleList(shop: shop, actor: actor, goods: goods) }
                    NavigationLink("Ajouter un article") { NewProduct(shop: shop) }
                }
                Section("Catalogue") {
                    TextField("Rechercher un article", text: $search)
                    ForEach(filtered) { item in
                        if tab == .stock {
                            NavigationLink { ProductDetail(item: item, actor: actor) } label: {
                                LabeledContent(item.title, value: "\(item.stockOnHand) unités")
                            }
                        } else {
                            Button { add(item) } label: { LabeledContent(item.title, value: "\(item.priceMinor) FCFA  ＋") }
                        }
                    }
                }
                if tab == .sell {
                    Section("Panier en cours") {
                        ForEach(lines, id: \.product.id) { line in
                            Stepper("\(line.units) × \(line.product.title)", onIncrement: { add(line.product) }, onDecrement: {
                                basket[line.product.id] = line.units == 1 ? nil : line.units - 1
                            })
                        }
                        TextField("Remise en FCFA", text: $discount).keyboardType(.numberPad)
                        if let total {
                            COVIButton("Encaisser \(total) FCFA") { quote = Quote(due: total) }
                        } else if !lines.isEmpty { Text("Vérifiez la remise et le total à encaisser.") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(COVITheme.cream).navigationTitle(tab.title)
        .sheet(item: $quote) { frozen in
            Checkout(due: frozen.due) { tender, received, confirmed in
                try BoutiqueLedger.sell(lines, discount: rebate, quote: frozen.due, tender: tender, received: received,
                    confirmed: confirmed, shop: shop, actor: actor, pin: pin, context: context)
                basket.removeAll(); discount = ""; quote = nil
                message = "Vente enregistrée · \(frozen.due) FCFA"
            }
        }
        .alert(message, isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("OK") {} }
    }
    private func add(_ item: CatalogItem) {
        let units = basket[item.id] ?? 0
        guard units < item.stockOnHand - item.stockReserved else { message = "Stock disponible atteint."; return }
        basket[item.id] = units + 1
        pin.touch()
    }
}

private struct Checkout: View {
    let due: Int64
    let commit: (Tender, Int64?, Bool) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tender = Tender.cash
    @State private var received = ""
    @State private var confirmed = false
    @State private var error = ""
    @State private var done = false
    var body: some View {
        NavigationStack {
            Form {
                Text("\(due) FCFA").font(.largeTitle.bold())
                Picker("Moyen de paiement", selection: $tender) {
                    ForEach(Tender.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.inline).onChange(of: tender) { _, _ in confirmed = false }
                if tender == .cash {
                    TextField("Montant reçu", text: $received).keyboardType(.numberPad)
                    if let cash = Int64(received), cash >= due { LabeledContent("Monnaie à rendre", value: "\(cash - due) FCFA") }
                } else { Toggle("Paiement reçu et vérifié sur \(tender.rawValue)", isOn: $confirmed) }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                COVIButton("Confirmer la vente") {
                    guard !done else { return }
                    do { try commit(tender, Int64(received), confirmed); done = true; HapticService.confirm() }
                    catch { self.error = error.localizedDescription }
                }.disabled(done || (tender == .cash ? (Int64(received) ?? -1) < due : !confirmed))
            }.navigationTitle("Encaissement").toolbar { Button("Fermer") { dismiss() } }
        }
    }
}
