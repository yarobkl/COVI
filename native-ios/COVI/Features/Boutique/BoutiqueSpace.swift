import SwiftUI
import SwiftData
import UIKit

@MainActor
struct BoutiqueSpace: View {
    let tab: BusinessTab
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    let startSale: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var textSize
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    #endif
    @Query private var goods: [CatalogItem]
    @Query private var sales: [CommerceOrder]
    @Query private var payments: [PaymentRecord]
    @State private var search = ""
    @State private var photoSearch = false
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
        .navigationBarTitleDisplayMode(tab == .sell && textSize.isAccessibilitySize ? .inline : .large)
        .toolbar {
            if tab == .home {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startSale) {
                        Image(systemName: "cart")
                    }
                    .accessibilityLabel("Vendre")
                }
            }
        }
        .sheet(isPresented: $photoSearch) {
            #if DEBUG && targetEnvironment(simulator)
            let root = diagnostics?.boutiquePhotoSample?.root
            #else
            let root: URL? = nil
            #endif
            BoutiqueSalePhotoSearch(shopID: shop.id, goods: goods, basket: basket,
                currency: shop.currencyCode, photoRoot: root) { item in
                photoSearch = false
                add(item)
            }
        }
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
            } else if diagnostics.scenario == .boutiquePhotoSearch {
                photoSearch = true
            }
        }
        #endif
    }

    private var homeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                todaySummary
                VStack(alignment: .leading, spacing: 8) {
                    COVISectionTitle("À suivre")
                    COVICard {
                        VStack(spacing: 4) {
                            NavigationLink { BoutiqueStockOverview(shop: shop, goods: goods) } label: {
                                let label = lowStock.count == 1 ? "1 article" : "\(lowStock.count) articles"
                                COVIIconRow(symbol: "exclamationmark.triangle",
                                    title: "Stock faible · \(label)",
                                    detail: lowStock.first.map { "\($0.title) · \($0.stockOnHand - $0.stockReserved) en stock" } ?? "Aucune alerte")
                            }
                            Divider()
                            NavigationLink { BoutiqueArrivals(shop: shop, actor: actor, goods: goods) } label: {
                                COVIIconRow(symbol: "shippingbox", title: "Arrivages", detail: "Consulter les lots et les livraisons")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    COVISectionTitle("Dernières ventes")
                    COVICard {
                        VStack(alignment: .leading, spacing: 4) {
                            let completed = sales.filter { $0.state == .completed }
                            let paymentsByOrder = Dictionary(grouping: payments, by: \.orderID)
                            if completed.isEmpty {
                                Text("Aucune vente pour le moment.")
                                    .foregroundStyle(COVITheme.secondaryText)
                            }
                            ForEach(Array(completed.prefix(4))) { sale in
                                if sale.id != completed.first?.id { Divider() }
                                let methods = Set((paymentsByOrder[sale.id] ?? []).map(\.method)).sorted()
                                let date = sale.createdAt.formatted(date: .abbreviated, time: .shortened)
                                NavigationLink { ReceiptDetail(order: sale, shop: shop) } label: {
                                    COVIIconRow(symbol: "bag",
                                        title: "#V-\(sale.id.uuidString.prefix(4).uppercased()) · \(COVIMoney.text(sale.totalMinor, currency: shop.currencyCode))",
                                        detail: (methods + [date]).joined(separator: " · "))
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var todaySummary: some View {
        let completed = todaysSales
        let count = completed.count
        let total = completed.reduce(Decimal.zero) { $0 + Decimal($1.totalMinor) }
        let todaysPayments = payments.filter { Calendar.current.isDateInToday($0.confirmedAt) }
        let cash = todaysPayments.filter { $0.method == Tender.cash.rawValue }
        let mobile = todaysPayments.filter { Tender(rawValue: $0.method)?.isMobileMoney == true }
        let other = todaysPayments.filter {
            $0.method != Tender.cash.rawValue && Tender(rawValue: $0.method)?.isMobileMoney != true
        }
        let paymentLayout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        return VStack(alignment: .leading, spacing: 12) {
            paymentLayout {
                Image(systemName: "chart.bar.fill")
                    .font(.title2).foregroundStyle(COVITheme.sand)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.13), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ventes du jour").font(.headline)
                    Text(homeMoney(total)).font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(count == 1 ? "1 vente" : "\(count) ventes").font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
            Rectangle().fill(.white.opacity(0.58)).frame(height: 1).accessibilityHidden(true)
            paymentLayout {
                amountSummary("Espèces", symbol: "banknote", payments: cash)
                if !textSize.isAccessibilitySize {
                    Rectangle().fill(.white.opacity(0.45)).frame(width: 1, height: 38)
                        .accessibilityHidden(true)
                }
                amountSummary("Mobile Money", symbol: "iphone", payments: mobile)
            }
            if !other.isEmpty {
                amountSummary("Autres moyens", symbol: "creditcard", payments: other)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [COVITheme.navy, Color(red: 0.02, green: 0.21, blue: 0.31)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func amountSummary(_ title: String, symbol: String, payments: [PaymentRecord]) -> some View {
        let amount = payments.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.title3).foregroundStyle(COVITheme.sand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(homeMoney(amount))
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func homeMoney(_ amount: Decimal) -> String {
        let currency = shop.currencyCode == "XAF" ? "FCFA" : shop.currencyCode
        return "\(amount.formatted(.number.grouping(.automatic))) \(currency)"
    }

    private var sellScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .accessibilityHidden(true)
                        TextField(textSize.isAccessibilitySize ? "Rechercher" : "Rechercher un article…", text: $search)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Rechercher un article")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .foregroundStyle(COVITheme.secondaryText)
                    .background(COVITheme.navy.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                    Button { photoSearch = true } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(COVITheme.navy)
                            .frame(width: 44, height: 44)
                            .background(COVITheme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(COVITheme.separator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rechercher un article par photo")
                }

                COVICard {
                    VStack(alignment: .leading, spacing: 14) {
                        COVISectionTitle("Panier en cours (\(lines.reduce(0) { $0 + $1.units }) articles)")
                        Divider()
                        if textSize.isAccessibilitySize, let total {
                            saleSummary(total)
                            Divider()
                        }
                        if lines.isEmpty {
                            Text("Touchez un produit pour l’ajouter au panier.")
                                .foregroundStyle(COVITheme.secondaryText)
                        }
                        ForEach(lines, id: \.product.id) { line in
                            let lineLayout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(spacing: 10))
                            lineLayout {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.product.title).font(.subheadline.weight(.semibold))
                                    if let subtotal = line.subtotal {
                                        Text(COVIMoney.text(subtotal, currency: shop.currencyCode))
                                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                                    } else {
                                        Text("Montant invalide").font(.subheadline).foregroundStyle(COVITheme.warning)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 0) {
                                    Button { basket[line.product.id] = line.units == 1 ? nil : line.units - 1 } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 17, weight: .semibold))
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }.accessibilityLabel("Retirer une unité de \(line.product.title)")
                                    Text("\(line.units)")
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .frame(minWidth: 15)
                                        .padding(.horizontal, textSize.isAccessibilitySize ? 6 : 0)
                                        .accessibilityLabel("Quantité : \(line.units)")
                                    Button { add(line.product) } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 17, weight: .semibold))
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
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
                                BoutiqueProductThumbnail(shopID: shop.id, itemID: item.id)
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
            if !textSize.isAccessibilitySize, let total {
                COVICard {
                    saleSummary(total)
                }
                .foregroundStyle(COVITheme.navy)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(COVITheme.cream)
            }
        }
    }

    private func saleSummary(_ total: Int64) -> some View {
        let amount = COVIMoney.text(total, currency: shop.currencyCode)
        let amountLayout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: textSize.isAccessibilitySize ? 8 : 16) {
            amountLayout {
                Text("Total :").font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(amount).font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if textSize.isAccessibilitySize {
                COVIButton("Encaisser") { quote = Quote(due: total) }
                    .accessibilityValue(amount)
            } else {
                COVIButton("Encaisser \(amount)") { quote = Quote(due: total) }
            }
        }
    }

    private var stockScreen: some View {
        List {
            Section {
                NavigationLink { BoutiqueStockOverview(shop: shop, goods: goods) } label: {
                    COVIIconRow(symbol: "shippingbox", title: "État des stocks", detail: "Quantités et alertes")
                }
                NavigationLink { BoutiqueArrivals(shop: shop, actor: actor, goods: goods) } label: {
                    COVIIconRow(symbol: "shippingbox", title: "Arrivages", detail: "Captures et réceptions")
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

@MainActor
private struct BoutiqueSalePhotoSearch: View {
    let shopID: UUID
    let goods: [CatalogItem]
    let basket: [UUID: Int]
    let currency: String
    let photoRoot: URL?
    let select: (CatalogItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    #endif
    @State private var work: Task<BoutiquePhotoSearch.Result, Error>?
    @State private var result: BoutiquePhotoSearch.Result?
    @State private var selectedID: UUID?
    @State private var error = ""

    private var available: [CatalogItem] {
        goods.filter {
            !$0.soldOut && $0.stockReserved >= 0 && $0.stockOnHand >= $0.stockReserved
                && $0.stockOnHand - $0.stockReserved > basket[$0.id, default: 0]
        }
    }

    private var selected: CatalogItem? {
        available.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    COVICard {
                        BoutiquePhotoInput(busy: work != nil, onPhoto: search)
                    }
                    if let result {
                        review(result)
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(COVITheme.warning) }
                }
                .padding(COVITheme.Metrics.screenPadding)
            }
            .foregroundStyle(COVITheme.navy)
            .background(COVIBackdrop())
            .navigationTitle("Recherche par photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    COVIButton("Confirmer et ajouter", systemImage: "checkmark") {
                        if let current = self.selected { select(current) }
                    }
                    .accessibilityHint("Ajoute une unité de \(selected.title) au panier")
                    .padding(COVITheme.Metrics.screenPadding)
                    .background(COVITheme.cream)
                }
            }
        }
        .onDisappear { work?.cancel() }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            if let sample = diagnostics?.boutiquePhotoSample { search(sample.photo) }
        }
        #endif
    }

    private func review(_ result: BoutiquePhotoSearch.Result) -> some View {
        let itemsByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let items = result.itemIDs.compactMap { itemsByID[$0] }
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))

        return VStack(alignment: .leading, spacing: 12) {
            COVISectionTitle("Reconnaissance visuelle")
            COVICard {
                layout {
                    if let photo = UIImage(data: result.preview) {
                        Image(uiImage: photo).resizable().scaledToFit()
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .accessibilityLabel("Photo utilisée pour la recherche")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Photo de recherche").font(.headline)
                        Text(items.isEmpty
                             ? "Aucun article disponible avec une photo locale."
                             : "Choisissez l’article qui correspond.")
                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    }
                }
            }
            if !items.isEmpty {
                COVISectionTitle("Articles à vérifier")
                ForEach(items) { item in
                    candidate(item)
                }
            }
        }
    }

    private func candidate(_ item: CatalogItem) -> some View {
        let chosen = item.id == selectedID
        let stock = item.stockOnHand - item.stockReserved - basket[item.id, default: 0]
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return Button { selectedID = item.id } label: {
            COVICard {
                layout {
                    BoutiqueProductThumbnail(shopID: shopID, itemID: item.id, root: photoRoot)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline)
                        Text(COVIMoney.text(item.priceMinor, currency: currency))
                            .font(.subheadline.weight(.semibold))
                        Text("Stock disponible : \(stock)").font(.caption)
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3).accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius)
                    .strokeBorder(chosen ? COVITheme.navy : .clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func search(_ photo: Data) {
        guard work == nil else { return }
        let ids = available.map(\.id)
        let establishment = shopID
        let root = photoRoot
        error = ""
        result = nil
        selectedID = nil
        let task = Task.detached(priority: .userInitiated) {
            try BoutiquePhotoSearch.analyze(photo: photo, shopID: establishment, itemIDs: ids, root: root)
        }
        work = task
        Task { @MainActor in
            defer { work = nil }
            do {
                let found = try await task.value
                guard !task.isCancelled else { return }
                result = found
                #if DEBUG && targetEnvironment(simulator)
                if let diagnostics, diagnostics.scenario == .boutiquePhotoSearch,
                   let first = found.itemIDs.first {
                    selectedID = first
                    work = nil
                    await diagnostics.signalAfterPresentation()
                }
                #endif
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
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

