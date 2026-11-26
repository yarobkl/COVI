import SwiftUI
import SwiftData

struct SalonCheckout: View {
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let visits: [SalonVisit]
    let team: [SalonStaff]
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.modelContext) private var db
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var visitID: UUID?
    @State private var clientID: UUID?
    @State private var stylist = ""
    @State private var basket: [UUID:Int] = [:]
    @State private var tender = Tender.cash
    @State private var confirm = false
    @State private var importing = false
    @State private var editing = false
    @State private var received = ""
    @State private var verified = false
    @State private var quoted: Int64?
    @State private var message = ""
    @State private var receipt: CommerceOrder?

    private var rowLayout: AnyLayout {
        textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    private var paymentTitle: LocalizedStringKey {
        if textSize.isAccessibilitySize { return "Encaisser" }
        return "Encaisser \(total.map { COVIMoney.text($0, currency: shop.currencyCode) } ?? "")"
    }
    private var total: Int64? { try? SalonLedger.total(basket: basket, menu: menu, shop: shop.id) }
    private var visit: SalonVisit? { visits.first { $0.id == visitID } }
    private var client: SalonClient? { clients.first { $0.id == clientID } }
    private var canPay: Bool {
        guard let total, client != nil, !stylist.isEmpty else { return false }
        return tender == .cash ? (Int64(received) ?? -1) >= total : verified
    }
    private func importVisit(_ appointment: SalonVisit) {
        visitID = appointment.id; clientID = appointment.client; stylist = appointment.stylist
        basket = [appointment.service: 1]; verified = false; received = ""; receipt = nil
    }

    var body: some View {
        checkoutContent
        .safeAreaInset(edge: .bottom) { payFooter }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Importer un RDV", systemImage: "calendar.badge.plus") { importing = true }
            }
        }
        .sheet(isPresented: $importing) {
            importSheet
        }
        .sheet(isPresented: $editing) {
            ticketEditor
        }
        .confirmationDialog(confirmationTitle, isPresented: $confirm) {
            Button("Je confirme avoir reçu · " + tender.rawValue) { pay() }
        }
        .onAppear(perform: prepare)
        .background(COVIBackdrop())
    }

    private var confirmationTitle: String {
        "Confirmer la réception de " + (quoted.map { COVIMoney.text($0, currency: shop.currencyCode) } ?? "") + " ?"
    }
    private var checkoutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ticketCard
                paymentCard
                if let receipt {
                    NavigationLink { ReceiptDetail(order: receipt, shop: shop) } label: {
                        Label("Voir et partager le dernier reçu", systemImage: "receipt")
                    }.frame(minHeight: 44)
                }
            }.foregroundStyle(COVITheme.navy).padding(18)
        }
    }
    private var payFooter: some View {
            VStack(spacing: 8) {
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(COVITheme.navy) }
                COVIButton(paymentTitle) {
                    quoted = total; confirm = true
                }.disabled(!canPay)
            }.padding(.horizontal, 18).padding(.vertical, 12).background(COVITheme.cream)
    }
    private func prepare() {
            if stylist.isEmpty { stylist = team.first(where: \.active)?.name ?? "" }
#if DEBUG && targetEnvironment(simulator)
            if let diagnostics, diagnostics.scenario == .salonCheckout,
               db.container === diagnostics.container, let sample = visits.first(where: { appointment in
                   !appointment.cancelled && appointment.receipt == nil && clients.first(where: { $0.id == appointment.client })?.name == "Mireille K."
               }) {
                importVisit(sample)
                for item in menu where !item.isService { basket[item.id] = 1 }
                received = "35000"
            }
#endif
        }

    private var ticketCard: some View {
                COVICard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ticket en cours · " + (client?.name ?? "Vente directe"))
                            .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        if basket.isEmpty {
                            Text("Importez un rendez-vous ou ajoutez une prestation et ses produits.")
                                .foregroundStyle(COVITheme.secondaryText)
                        }
                        ForEach(menu.filter { basket[$0.id] != nil }.sorted {
                            if $0.isService != $1.isService { return $0.isService }
                            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                        }) { item in
                            Divider()
                            rowLayout {
                                Image(systemName: item.isService ? "scissors" : "shippingbox")
                                    .font(.system(size: 24)).frame(width: 42, height: 48)
                                    .background(COVITheme.sand.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.subheadline.bold())
                                    Text(item.isService ? "Collaborateur : \(stylist)" : "Quantité : \(basket[item.id] ?? 0) · \(item.stockOnHand - item.stockReserved) disponible(s)")
                                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                }
                                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                                if let subtotal = BoutiqueLedger.Line(product: item, units: basket[item.id] ?? 0).subtotal {
                                    Text(COVIMoney.text(subtotal, currency: shop.currencyCode)).font(.subheadline.bold())
                                }
                            }
                        }
                        Button("Modifier le ticket", systemImage: "plus.circle") { editing = true }
                            .frame(minHeight: 44)
                    }
                }
    }

    private var paymentCard: some View {
                COVICard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Règlement externe", systemImage: "creditcard").font(.title3.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Tender.allCases, id: \.self) { option in
                                    Button {
                                        tender = option; verified = false
                                    } label: {
                                        Text(option.rawValue).font(.subheadline.bold())
                                            .padding(.horizontal, 16).frame(minHeight: 44)
                                            .foregroundStyle(tender == option ? .white : COVITheme.navy)
                                            .background(tender == option ? COVITheme.navy : COVITheme.cream,
                                                in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain)
                                    .accessibilityAddTraits(tender == option ? .isSelected : [])
                                }
                            }
                        }
                        Divider()
                        rowLayout {
                            Text("Total à encaisser").font(.headline)
                            if !textSize.isAccessibilitySize { Spacer() }
                            Text(total.map { COVIMoney.text($0, currency: shop.currencyCode) } ?? "Montant invalide")
                                .font(.title3.bold())
                        }.padding(12)
                        .background(COVITheme.sand.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        if tender == .cash {
                            rowLayout {
                                Text("Montant reçu")
                                HStack {
                                    TextField("0", text: $received).keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing).accessibilityLabel("Montant reçu")
                                    Text(shop.currencyCode)
                                }
                            }
                            if let total, let cash = Int64(received), cash >= total {
                                LabeledContent("Monnaie à rendre", value: COVIMoney.text(cash - total, currency: shop.currencyCode))
                                    .foregroundStyle(COVITheme.success)
                            }
                        } else {
                            Text("Vérifiez la réception sur le compte du commerce avant de confirmer. Une référence seule ne prouve pas le paiement.")
                                .font(.caption).foregroundStyle(COVITheme.secondaryText)
                            Toggle("J’ai vérifié la réception du paiement", isOn: $verified)
                        }
                    }
                }
    }

    private var importSheet: some View {
            NavigationStack {
                List {
                    Button("Vente directe") {
                        visitID = nil; basket = [:]; received = ""; verified = false; importing = false
                    }
                    ForEach(visits.filter { !$0.cancelled && $0.receipt == nil }) { appointment in
                        Button {
                            importVisit(appointment); importing = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(clients.first { $0.id == appointment.client }?.name ?? "Client")
                                Text(appointment.start.formatted()).font(.caption)
                            }
                        }
                    }
                }.navigationTitle("Importer un rendez-vous")
                .toolbar { Button("Fermer") { importing = false } }
            }
    }

    private var ticketEditor: some View {
            NavigationStack {
                Form {
                    Picker("Client", selection: $clientID) {
                        Text("Choisir").tag(nil as UUID?)
                        ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(visitID != nil)
                    Picker("Collaborateur crédité", selection: $stylist) {
                        Text("Choisir").tag("")
                        ForEach(team.filter { $0.active || $0.name == stylist }) { Text($0.name).tag($0.name) }
                    }.disabled(visitID != nil)
                    ForEach([true, false], id: \.self) { services in
                        Section(services ? "Prestations" : "Produits de soin") {
                            ForEach(menu.filter { $0.isService == services && (!$0.soldOut || visit?.service == $0.id) }) { item in
                                Stepper(value: Binding(get: { basket[item.id] ?? 0 }, set: {
                                    basket[item.id] = $0 == 0 ? nil : $0
                                    verified = false
                                }), in: 0...999) {
                                    VStack(alignment: .leading) {
                                        Text("\(basket[item.id] ?? 0) × \(item.title)")
                                        Text(COVIMoney.text(item.priceMinor, currency: shop.currencyCode)).font(.caption)
                                    }
                                }.disabled(visit?.service == item.id)
                            }
                        }
                    }
                    if clients.isEmpty { Text("Créez une fiche dans Clients pour encaisser une prestation.") }
                    if menu.isEmpty { Text("Ajoutez vos prestations dans Plus → Catalogue du salon.") }
                    if team.isEmpty { Text("Ajoutez votre équipe dans Plus avant d’encaisser.") }
                }.navigationTitle("Modifier le ticket")
                .toolbar { Button("Terminé") { editing = false } }
            }
    }

    private func pay() {
        guard let client, let quoted else { return }
        guard visitID == nil || visit != nil else { message = SalonFault.stale.localizedDescription; return }
        do {
            receipt = try SalonLedger.pay(shop: shop, actor: actor, pin: pin, client: client,
                team: stylist, visit: visit, basket: basket, menu: menu, tender: tender,
                confirmed: tender == .cash || verified, quote: quoted, received: Int64(received), db: db)
            visitID = nil; basket = [:]; received = ""; verified = false
            message = "Paiement enregistré."; HapticService.confirm()
        } catch { message = error.localizedDescription; HapticService.error() }
    }
}

struct SalonCatalog: View {
    let shop: Establishment
    let menu: [CatalogItem]
    let actor: UUID
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.modelContext) private var db
    @State private var adding = false
    @State private var search = ""
    @State private var showingServices = true
    @State private var name = ""
    @State private var price = ""
    @State private var qty = ""
    @State private var percent = 0
    @State private var service = true
    @State private var message = ""
    private var rowLayout: AnyLayout {
        textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }
    private var filtered: [CatalogItem] {
        menu.filter { $0.isService == showingServices &&
            (search.isEmpty || $0.title.localizedStandardContains(search)) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Catalogue", selection: $showingServices) {
                    Text("Prestations (\(menu.filter(\.isService).count))").tag(true)
                    Text("Produits (\(menu.filter { !$0.isService }.count))").tag(false)
                }.pickerStyle(.segmented)
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 20)).accessibilityHidden(true)
                    TextField("Rechercher une prestation ou un soin…", text: $search)
                }.padding(14).background(COVITheme.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Catalogue vide" : "Aucun résultat",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Ajoutez une référence ou adaptez votre recherche."))
                } else {
                    COVICard {
                        VStack(spacing: 0) {
                            ForEach(filtered) { item in
                                NavigationLink {
                                    SalonCatalogEditor(shop: shop, item: item, actor: actor)
                                } label: {
                                    rowLayout {
                                        Image(systemName: item.isService ? "scissors" : "shippingbox")
                                            .font(.system(size: 24)).frame(width: 48, height: 56)
                                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title).font(.headline)
                                            Text(item.soldOut ? "Suspendu" : (item.isService ? "Prestation" : "\(item.stockOnHand - item.stockReserved) disponible(s)"))
                                                .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                        }
                                        if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                                        Text(COVIMoney.text(item.priceMinor, currency: shop.currencyCode))
                                            .font(.subheadline.bold())
                                        if !textSize.isAccessibilitySize {
                                            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                                        }
                                    }.padding(.vertical, 12).foregroundStyle(COVITheme.navy)
                                }.buttonStyle(.plain)
                                if item.id != filtered.last?.id { Divider() }
                            }
                        }
                    }
                }
            }.padding(18)
        }
        .background(COVIBackdrop())
        .navigationTitle("Catalogue salon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Ajouter", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                addForm.toolbar { Button("Fermer") { adding = false } }
            }
        }
    }
    private var addForm: some View {
        Form {
            Section("Nouvelle référence") {
                Picker("Type", selection: $service) { Text("Prestation").tag(true); Text("Produit").tag(false) }.pickerStyle(.segmented)
                TextField("Libellé", text: $name)
                TextField("Prix " + shop.currencyCode, text: $price).keyboardType(.numberPad)
                if !service { TextField("Stock initial", text: $qty).keyboardType(.numberPad) }
                Stepper("Commission : \(percent) %", value: $percent, in: 0...100)
                Button("Ajouter au catalogue") {
                    guard let amount = Int64(price), amount > 0,
                          let count = Int(service ? "0" : qty), count >= 0 else { message = SalonFault.invalid.localizedDescription; return }
                    do {
                        try SalonLedger.createCatalog(shop: shop, actor: actor, title: name,
                            price: amount, service: service, quantity: count, percent: percent, db: db)
                        name = ""; price = ""; qty = ""; message = "Référence ajoutée."
                    } catch { message = error.localizedDescription }
                }
            }
            if !message.isEmpty { Text(message) }
        }.navigationTitle("Nouvelle référence")
    }
}

private struct SalonCatalogEditor: View {
    let shop: Establishment
    let item: CatalogItem
    let actor: UUID
    @Environment(\.modelContext) private var db
    @Query private var movements: [StockMovement]
    @State private var title = ""
    @State private var price = ""
    @State private var percent = 0
    @State private var counted = ""
    @State private var reason = ""
    @State private var changingAvailability = false
    @State private var message = ""

    init(shop: Establishment, item: CatalogItem, actor: UUID) {
        self.shop = shop; self.item = item; self.actor = actor
        let id = item.id
        _movements = Query(filter: #Predicate<StockMovement> { $0.itemID == id },
                           sort: \.createdAt, order: .reverse)
    }

    var body: some View {
        Form {
            Section(item.isService ? "Prestation" : "Produit de soin") {
                TextField("Libellé", text: $title)
                TextField("Prix " + shop.currencyCode, text: $price).keyboardType(.numberPad)
                Stepper("Commission : \(percent) %", value: $percent, in: 0...100)
                Button("Enregistrer les modifications") {
                    do {
                        try SalonLedger.editCatalog(item, shop: shop, actor: actor,
                            title: title, price: Int64(price) ?? 0, percent: percent, db: db)
                        message = "Catalogue mis à jour. Les anciens reçus restent inchangés."
                    } catch { message = error.localizedDescription }
                }
                Label(item.soldOut ? "Vente suspendue" : "Disponible à la vente",
                      systemImage: item.soldOut ? "pause.circle" : "checkmark.circle")
                Button(item.soldOut ? "Remettre en vente" : "Suspendre les ventes") {
                    changingAvailability = true
                }
            }
            if !item.isService {
                Section("Inventaire du produit") {
                    LabeledContent("Physique", value: String(item.stockOnHand))
                    LabeledContent("Réservé", value: String(item.stockReserved))
                    TextField("Quantité réellement comptée", text: $counted).keyboardType(.numberPad)
                    TextField("Motif de l'inventaire", text: $reason)
                    Button("Corriger le stock") {
                        do {
                            try SalonLedger.adjustProductStock(item, shop: shop, actor: actor,
                                counted: Int(counted) ?? -1, reason: reason, db: db)
                            counted = ""; reason = ""; message = "Inventaire enregistré."
                        } catch { message = error.localizedDescription }
                    }
                    ForEach(movements) { movement in
                        VStack(alignment: .leading) {
                            Text("\(movement.delta > 0 ? "+" : "")\(movement.delta) · \(movement.reason)")
                            Text(movement.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
        }
        .navigationTitle("Fiche catalogue")
        .onAppear {
            title = item.title; price = String(item.priceMinor); percent = item.salonPercent
        }
        .confirmationDialog(item.soldOut ? "Réactiver cette référence ?" : "Suspendre cette référence ?",
                            isPresented: $changingAvailability) {
            Button(item.soldOut ? "Réactiver" : "Suspendre les ventes") {
                do {
                    try SalonLedger.setCatalogAvailability(item, shop: shop, actor: actor,
                        available: item.soldOut, db: db)
                    message = "Disponibilité enregistrée ; historique conservé."
                } catch { message = error.localizedDescription }
            }
        } message: {
            Text("Les anciennes réservations, les commissions et les reçus restent conservés.")
        }
    }
}

struct SalonReport: View {
    let sales: [SalonSaleLine]
    let visits: [SalonVisit]
    let currency: String
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var date = Date()
    @State private var monthly = true
    @State private var choosingPeriod = false

    var body: some View {
        let granularity: Calendar.Component = monthly ? .month : .day
        let rows = sales.filter { Calendar.current.isDate($0.date, equalTo: date, toGranularity: granularity) }
        let periodVisits = visits.filter {
            !$0.cancelled && Calendar.current.isDate($0.start, equalTo: date, toGranularity: granularity)
        }
        let services = total(rows.filter(\.service), by: \.gross)
        let products = total(rows.filter { !$0.service }, by: \.gross)
        let commissions = total(rows, by: \.commission)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard(services: services, products: products)
                COVISectionTitle("Activité et commissions de l’équipe")
                teamCard(salesByPerson: Dictionary(grouping: rows, by: \.stylist),
                         visitsByPerson: Dictionary(grouping: periodVisits, by: \.stylist))
                COVICard {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Commissions équipe", value: money(commissions))
                        Divider()
                        LabeledContent("Après commissions, hors charges", value: money(services + products - commissions))
                    }
                    .font(.subheadline)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
        }
        .background(COVIBackdrop())
        .navigationTitle("Rapports salon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { choosingPeriod = true } label: {
                Label(periodTitle, systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Période du rapport")
            .accessibilityValue(periodTitle)
        }
        .sheet(isPresented: $choosingPeriod) {
            NavigationStack {
                Form {
                    Picker("Période", selection: $monthly) {
                        Text("Jour").tag(false)
                        Text("Mois").tag(true)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date de référence", selection: $date, displayedComponents: .date)
                }
                .navigationTitle("Période du rapport")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { choosingPeriod = false }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .salonReport {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var periodTitle: String {
        monthly ? date.formatted(.dateTime.month(.abbreviated).year()) :
            date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func summaryCard(services: Decimal, products: Decimal) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(COVITheme.sand)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chiffre d’affaires total").font(.subheadline)
                    Text(money(services + products)).font(.title.bold())
                }
                .accessibilityElement(children: .combine)
            }
            Rectangle().fill(.white.opacity(0.4)).frame(height: 1).accessibilityHidden(true)
            layout {
                reportMoney("Prestations", amount: services, symbol: "scissors")
                reportMoney("Revente produits", amount: products, symbol: "shippingbox")
            }
        }
        .foregroundStyle(.white)
        .padding(COVITheme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius))
    }

    private func teamCard(salesByPerson: [String: [SalonSaleLine]], visitsByPerson: [String: [SalonVisit]]) -> some View {
        let people = Set(salesByPerson.keys).union(visitsByPerson.keys).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return COVICard {
            VStack(alignment: .leading, spacing: 8) {
                if people.isEmpty {
                    Text("Aucune activité sur cette période.")
                        .foregroundStyle(COVITheme.secondaryText)
                }
                ForEach(people, id: \.self) { person in
                    if person != people.first { Divider() }
                    let activity = salesByPerson[person] ?? []
                    let visitsCount = visitsByPerson[person]?.count ?? 0
                    let tickets = Set(activity.map(\.order)).count
                    layout {
                        COVIIconRow(symbol: "person", title: person,
                            detail: "\(tickets) ticket(s) · \(visitsCount) RDV · \(money(total(activity, by: \.gross)))",
                            accessory: nil)
                        Text("Part · " + money(total(activity, by: \.commission)))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(COVITheme.champagne, in: Capsule())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func reportMoney(_ title: String, amount: Decimal, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(COVITheme.sand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(money(amount)).font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func total(_ rows: [SalonSaleLine], by field: KeyPath<SalonSaleLine, Int64>) -> Decimal {
        rows.reduce(Decimal.zero) { $0 + Decimal($1[keyPath: field]) }
    }

    private func money(_ amount: Decimal) -> String {
        "\(amount.formatted(.number.grouping(.automatic))) \(currency == "XAF" ? "FCFA" : currency)"
    }
}
