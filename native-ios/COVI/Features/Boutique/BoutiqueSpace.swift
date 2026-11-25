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
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    #endif
    @Query private var goods: [CatalogItem]
    @Query private var sales: [CommerceOrder]
    @Query private var payments: [PaymentRecord]
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
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.establishmentID == id })
    }
    var lines: [BoutiqueLedger.Line] {
        goods.compactMap { item in basket[item.id].map { BoutiqueLedger.Line(product: item, units: $0) } }
    }
    var rebate: Int64 { discount.isEmpty ? 0 : Int64(discount) ?? -1 }
    var total: Int64? { try? BoutiqueLedger.total(lines, discount: rebate) }
    var filtered: [CatalogItem] {
        goods.filter { (tab == .stock || !$0.soldOut) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    var todaysSales: [CommerceOrder] {
        sales.filter { $0.state == .completed && Calendar.current.isDateInToday($0.createdAt) }
    }
    var lowStock: [CatalogItem] {
        goods.filter { !$0.soldOut && $0.stockOnHand - $0.stockReserved <= 2 }
    }
    var body: some View {
        Group {
            if tab == .home { homeScreen }
            else if tab == .sell { sellScreen }
            else { stockScreen }
        }
        .background(COVIBackdrop())
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $quote) { frozen in
            Checkout(due: frozen.due, shop: shop) { tender, received, confirmed in
                let order = try BoutiqueLedger.sell(lines, discount: rebate, quote: frozen.due, tender: tender, received: received,
                    confirmed: confirmed, shop: shop, actor: actor, pin: pin, context: context)
                basket.removeAll(); discount = ""
                return order
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Boutique", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("OK") {}
        } message: { Text(message) }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard let diagnostics, diagnostics.shop.id == shop.id,
                  context.container === diagnostics.container, tab == .sell else { return }
            basket = diagnostics.basket
            if diagnostics.scenario == .checkout {
                quote = Quote(due: diagnostics.due)
            }
        }
        #endif
    }

    private var homeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title).foregroundStyle(COVITheme.sand)
                            .frame(width: 65, height: 65)
                            .background(.white.opacity(0.13), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ventes du jour").font(.headline)
                            Text(COVIMoney.text(todaysSales.reduce(Int64(0)) { $0 + $1.totalMinor }, currency: shop.currencyCode))
                                .font(.system(size: 27, weight: .bold))
                                .minimumScaleFactor(0.72).lineLimit(1)
                            Text("\(todaysSales.count) ventes").font(.subheadline)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.58)).frame(height: 1)
                    let todaysPayments = payments.filter { Calendar.current.isDateInToday($0.confirmedAt) }
                    HStack {
                        amountSummary("Espèces", symbol: "banknote",
                            amount: todaysPayments.filter { $0.method == Tender.cash.rawValue }
                                .reduce(Int64(0)) { $0 + $1.amountMinor })
                        Rectangle().fill(.white.opacity(0.45)).frame(width: 1, height: 42)
                        amountSummary("Mobile Money", symbol: "iphone",
                            amount: todaysPayments.filter { $0.method != Tender.cash.rawValue }
                                .reduce(Int64(0)) { $0 + $1.amountMinor })
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
                .background(LinearGradient(colors: [COVITheme.navy, Color(red: 0.02, green: 0.21, blue: 0.31)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20))

                COVIButton("Vendre", systemImage: "cart") { startSale() }

                VStack(alignment: .leading, spacing: 12) {
                    COVISectionTitle("À suivre")
                    COVICard {
                        VStack(spacing: 12) {
                            NavigationLink { BoutiqueStockOverview(shop: shop, goods: goods) } label: {
                                COVIIconRow(symbol: "exclamationmark.triangle",
                                    title: "Stock faible · \(lowStock.count) articles",
                                    detail: lowStock.first.map { "\($0.title) — \($0.stockOnHand - $0.stockReserved) restant(s)" } ?? "Aucune alerte")
                            }
                            Divider()
                            NavigationLink { BaleList(shop: shop, actor: actor, goods: goods) } label: {
                                COVIIconRow(symbol: "shippingbox", title: "Arrivages", detail: "Consulter les lots et les livraisons")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    COVISectionTitle("Dernières ventes")
                    COVICard {
                        VStack(alignment: .leading, spacing: 12) {
                            let completed = sales.filter { $0.state == .completed }
                            if completed.isEmpty {
                                Text("Aucune vente pour le moment.")
                                    .foregroundStyle(COVITheme.secondaryText)
                            }
                            ForEach(Array(completed.prefix(4))) { sale in
                                if sale.id != completed.first?.id { Divider() }
                                NavigationLink { ReceiptDetail(order: sale, shop: shop) } label: {
                                    COVIIconRow(symbol: "bag",
                                        title: "#V-\(sale.id.uuidString.prefix(4).uppercased()) · \(COVIMoney.text(sale.totalMinor, currency: shop.currencyCode))",
                                        detail: sale.createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func amountSummary(_ title: String, symbol: String, amount: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(COVITheme.sand)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(COVIMoney.text(amount, currency: shop.currencyCode))
                    .font(.subheadline.weight(.bold))
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var sellScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Rechercher un produit...", text: $search).autocorrectionDisabled()
                }
                .padding(15).foregroundStyle(COVITheme.secondaryText)
                .background(COVITheme.navy.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))

                COVICard {
                    VStack(alignment: .leading, spacing: 14) {
                        COVISectionTitle("Panier en cours (\(lines.reduce(0) { $0 + $1.units }) articles)")
                        Divider()
                        if lines.isEmpty {
                            Text("Touchez un produit pour l’ajouter au panier.")
                                .foregroundStyle(COVITheme.secondaryText)
                        }
                        ForEach(lines, id: \.product.id) { line in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.product.title).font(.subheadline.weight(.semibold))
                                    if let subtotal = line.subtotal {
                                        Text(COVIMoney.text(subtotal, currency: shop.currencyCode))
                                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                                    } else {
                                        Text("Montant invalide").font(.subheadline).foregroundStyle(COVITheme.warning)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 0) {
                                    Button { basket[line.product.id] = line.units == 1 ? nil : line.units - 1 } label: {
                                        Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
                                    }.accessibilityLabel("Retirer une unité de \(line.product.title)")
                                    Text("\(line.units)").fontWeight(.semibold).frame(minWidth: 15)
                                    Button { add(line.product) } label: {
                                        Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                                    }.accessibilityLabel("Ajouter une unité de \(line.product.title)")
                                }
                                .foregroundStyle(COVITheme.navy)
                                .buttonStyle(.borderless)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(COVITheme.navy.opacity(0.28), lineWidth: 1)
                                        .allowsHitTesting(false)
                                }
                            }
                            Divider()
                        }
                        HStack {
                            Text("Remise (\(shop.currencyCode))")
                            TextField("0", text: $discount).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Montant de la remise")
                        }
                    }
                }
                if !lines.isEmpty && total == nil {
                    Text("Vérifiez la remise et le total à encaisser.").foregroundStyle(.red)
                }

                COVISectionTitle("Catalogue")
                if filtered.isEmpty {
                    ContentUnavailableView(goods.isEmpty ? "Aucun article" : "Aucun résultat",
                        systemImage: "shippingbox",
                        description: Text(goods.isEmpty ? "Ajoutez votre premier article dans Stock avant d’encaisser." : "Essayez un autre nom de produit."))
                }
                ForEach(filtered) { item in
                    Button { add(item) } label: {
                        COVICard {
                            HStack(spacing: 12) {
                                Image(systemName: "bag")
                                    .font(.title2).foregroundStyle(COVITheme.navy)
                                    .frame(width: 65, height: 70)
                                    .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title).font(.headline)
                                    Text(COVIMoney.text(item.priceMinor, currency: shop.currencyCode))
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(item.stockOnHand - item.stockReserved) disponibles")
                                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "plus.circle.fill").font(.title2)
                            }
                            .foregroundStyle(COVITheme.navy)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(18)
        }
        .safeAreaInset(edge: .bottom) {
            if let total {
                COVICard {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Total :").font(.headline)
                            Spacer()
                            Text(COVIMoney.text(total, currency: shop.currencyCode)).font(.title3.bold())
                        }
                        COVIButton("Encaisser \(COVIMoney.text(total, currency: shop.currencyCode))") {
                            quote = Quote(due: total)
                        }
                    }
                }
                .foregroundStyle(COVITheme.navy)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(COVITheme.cream)
            }
        }
    }

    private var stockScreen: some View {
        List {
            Section {
                NavigationLink { BoutiqueStockOverview(shop: shop, goods: goods) } label: {
                    COVIIconRow(symbol: "shippingbox", title: "État des stocks", detail: "Quantités et alertes")
                }
                NavigationLink { BaleList(shop: shop, actor: actor, goods: goods) } label: {
                    COVIIconRow(symbol: "shippingbox", title: "Arrivages de balles", detail: "Lots et réceptions")
                }
                NavigationLink { NewProduct(shop: shop, actor: actor) } label: {
                    COVIIconRow(symbol: "plus", title: "Ajouter un article", detail: nil)
                }
            }
            Section("Catalogue") {
                TextField("Rechercher un produit...", text: $search)
                ForEach(filtered) { item in
                    NavigationLink { ProductDetail(shop: shop, item: item, actor: actor) } label: {
                        COVIIconRow(symbol: "bag", title: item.title,
                            detail: item.soldOut ? "En pause · \(item.stockOnHand)" : "\(item.stockOnHand - item.stockReserved) disponibles",
                            accessory: nil)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    private func add(_ item: CatalogItem) {
        let units = basket[item.id] ?? 0
        guard !item.soldOut, item.stockReserved >= 0,
              item.stockOnHand >= item.stockReserved,
              units < item.stockOnHand - item.stockReserved else {
            message = "Article indisponible ou stock épuisé."; return
        }
        basket[item.id] = units + 1
        pin.touch()
    }
}

private struct Checkout: View {
    let due: Int64
    let shop: Establishment
    let commit: (Tender, Int64?, Bool) throws -> CommerceOrder
    @Environment(\.dismiss) private var dismiss
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.modelContext) private var context
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    #endif
    @State private var tender = Tender.cash
    @State private var received = ""
    @State private var confirmed = false
    @State private var error = ""
    @State private var receipt: CommerceOrder?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Encaissement")
                            .font(.title2.weight(.bold))
                        Text(COVIMoney.text(due, currency: shop.currencyCode))
                            .font(.system(size: 35, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)

                    COVICard {
                        VStack(spacing: 0) {
                            ForEach(Tender.allCases, id: \.self) { option in
                                Button {
                                    tender = option; confirmed = false
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: option == .cash ? "banknote" : "iphone")
                                            .font(.title3).frame(width: 30)
                                            .accessibilityHidden(true)
                                        Text(option.rawValue).font(.headline)
                                        Spacer()
                                        Image(systemName: tender == option ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .accessibilityHidden(true)
                                    }
                                    .foregroundStyle(COVITheme.navy)
                                    .padding(.vertical, 6)
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(tender == option ? .isSelected : [])
                                if option != Tender.allCases.last { Divider() }
                            }
                        }
                    }

                    Label {
                        Text("Confirmation manuelle de réception. Paiement effectué hors de COVI.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundStyle(COVITheme.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(COVITheme.warningTint, in: RoundedRectangle(cornerRadius: 16))

                    if tender == .cash {
                        COVICard {
                            VStack(spacing: 15) {
                                HStack {
                                    Text("Montant reçu").font(.headline)
                                    Spacer()
                                    HStack(spacing: 6) {
                                        TextField("0", text: $received)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.trailing)
                                            .accessibilityLabel("Montant reçu")
                                        Text(shop.currencyCode == "XAF" ? "FCFA" : shop.currencyCode)
                                    }
                                    .font(.headline)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .frame(maxWidth: 190)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(COVITheme.navy.opacity(0.28), lineWidth: 1)
                                            .allowsHitTesting(false)
                                    }
                                }
                                if let cash = Int64(received), cash >= due {
                                    HStack {
                                        Label("Monnaie à rendre", systemImage: "arrow.triangle.2.circlepath")
                                        Spacer()
                                        Text(COVIMoney.text(cash - due, currency: shop.currencyCode))
                                            .font(.headline)
                                    }
                                    .foregroundStyle(COVITheme.success)
                                    .padding(12)
                                    .background(COVITheme.successTint, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    } else {
                        COVICard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Le paiement a lieu hors de COVI. Vérifiez-le directement sur le compte \(tender.rawValue) du commerce.")
                                    .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                Toggle("J’ai vérifié la réception du paiement", isOn: $confirmed)
                                    .tint(COVITheme.success)
                            }
                        }
                    }

                    if let receipt {
                        COVICard {
                            Label("Paiement confirmé en caisse", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(COVITheme.success)
                        }
                        NavigationLink("Voir et partager le reçu") { ReceiptDetail(order: receipt, shop: shop) }
                        COVIButton("Terminer") { dismiss() }
                    }
                }
                .foregroundStyle(COVITheme.navy)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if receipt == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if !error.isEmpty {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        COVIButton("Confirmer la vente & voir le reçu") {
                            do { receipt = try commit(tender, Int64(received), confirmed); HapticService.confirm() }
                            catch { self.error = error.localizedDescription; HapticService.error() }
                        }
                        .disabled(tender == .cash ? (Int64(received) ?? -1) < due : !confirmed)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(COVITheme.cream)
                }
            }
            .background(COVIBackdrop())
            .toolbar { Button("Fermer") { dismiss() } }
        }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard let diagnostics, diagnostics.scenario == .checkout,
                  diagnostics.shop.id == shop.id, diagnostics.due == due,
                  context.container === diagnostics.container else { return }
            received = String(diagnostics.cashReceived)
        }
        #endif
    }
}

