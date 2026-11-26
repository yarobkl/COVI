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
                COVIButton("Encaisser \(total.map { COVIMoney.text($0, currency: shop.currencyCode) } ?? "")") {
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
                        Label("Ticket en cours · " + (client?.name ?? "Vente directe"), systemImage: "person.crop.circle")
                            .font(.title3.bold())
                        if basket.isEmpty {
                            Text("Importez un rendez-vous ou ajoutez une prestation et ses produits.")
                                .foregroundStyle(COVITheme.secondaryText)
                        }
                        ForEach(menu.filter { basket[$0.id] != nil }.sorted {
                            if $0.isService != $1.isService { return $0.isService }
                            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                        }) { item in
                            Divider()
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.isService ? "scissors" : "shippingbox")
                                    .font(.title2).frame(width: 42, height: 48)
                                    .background(COVITheme.sand.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.subheadline.bold())
                                    Text(item.isService ? "Collaborateur : \(stylist)" : "Quantité : \(basket[item.id] ?? 0) · \(item.stockOnHand - item.stockReserved) disponible(s)")
                                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                }
                                Spacer(minLength: 0)
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
                        HStack {
                            Text("Total à encaisser").font(.headline)
                            Spacer()
                            Text(total.map { COVIMoney.text($0, currency: shop.currencyCode) } ?? "Montant invalide")
                                .font(.title3.bold())
                        }.padding(12)
                        .background(COVITheme.sand.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        if tender == .cash {
                            HStack {
                                Text("Montant reçu")
                                TextField("0", text: $received).keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing).accessibilityLabel("Montant reçu")
                                Text(shop.currencyCode)
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
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
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
                                    HStack(spacing: 12) {
                                        Image(systemName: item.isService ? "scissors" : "shippingbox")
                                            .font(.title2).frame(width: 48, height: 56)
                                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title).font(.headline)
                                            Text(item.soldOut ? "Suspendu" : (item.isService ? "Prestation" : "\(item.stockOnHand - item.stockReserved) disponible(s)"))
                                                .font(.caption).foregroundStyle(COVITheme.secondaryText)
                                        }
                                        Spacer(minLength: 0)
                                        Text(COVIMoney.text(item.priceMinor, currency: shop.currencyCode))
                                            .font(.subheadline.bold())
                                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
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
    @State private var date = Date()
    @State private var monthly = true
    func includes(_ d: Date) -> Bool { Calendar.current.isDate(d, equalTo: date, toGranularity: monthly ? .month : .day) }
    var body: some View {
        let rows = sales.filter { includes($0.date) }
        let periodVisits = visits.filter { includes($0.start) }
        let gross = rows.reduce(Int64(0)) { $0 + $1.gross }
        let services = rows.filter(\.service).reduce(Int64(0)) { $0 + $1.gross }
        let products = rows.filter { !$0.service }.reduce(Int64(0)) { $0 + $1.gross }
        let commissions = rows.reduce(Int64(0)) { $0 + $1.commission }
        let people = Array(Set(rows.map(\.stylist) + periodVisits.map(\.stylist))).sorted()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Picker("Période", selection: $monthly) {
                        Text("Jour").tag(false)
                        Text("Mois").tag(true)
                    }.pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 15) {
                        Image(systemName: "chart.bar.fill")
                            .font(.largeTitle).foregroundStyle(COVITheme.sand)
                            .frame(width: 62, height: 62)
                            .background(.white.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chiffre d’affaires total :").font(.headline)
                            Text(COVIMoney.text(gross, currency: currency))
                                .font(.system(size: 29, weight: .bold))
                                .minimumScaleFactor(0.7).lineLimit(1)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.48)).frame(height: 1)
                    HStack(spacing: 8) {
                        reportMoney("Prestations", amount: services, symbol: "scissors")
                        Rectangle().fill(.white.opacity(0.48)).frame(width: 1, height: 45)
                        reportMoney("Revente produits", amount: products, symbol: "shippingbox")
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: 20))

                COVISectionTitle("Activité & Commissions équipe")
                COVICard {
                    if people.isEmpty {
                        Text("Aucune activité sur cette période.")
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                    ForEach(people, id: \.self) { person in
                        let activity = rows.filter { $0.stylist == person }
                        VStack(alignment: .leading, spacing: 9) {
                            COVIIconRow(symbol: "person.crop.circle", title: person,
                                detail: "\(Set(activity.map(\.order)).count) tickets · CA : \(COVIMoney.text(activity.reduce(0) { $0 + $1.gross }, currency: currency))",
                                accessory: nil)
                            HStack {
                                COVIBadge(title: "Part : \(COVIMoney.text(activity.reduce(0) { $0 + $1.commission }, currency: currency))")
                                Spacer()
                                Text("\(periodVisits.filter { !$0.cancelled && $0.stylist == person }.count) RDV")
                                    .font(.caption).foregroundStyle(COVITheme.secondaryText)
                            }
                        }
                        Divider()
                    }
                }
                COVICard {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Commissions équipe", value: COVIMoney.text(commissions, currency: currency))
                        Divider()
                        LabeledContent("Après commissions · hors charges", value: COVIMoney.text(gross - commissions, currency: currency))
                    }
                    .font(.subheadline)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(18)
        }
        .background(COVIBackdrop())
        .navigationTitle("Rapports salon")
    }

    private func reportMoney(_ title: String, amount: Int64, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(COVITheme.sand)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(COVIMoney.text(amount, currency: currency))
                    .font(.subheadline.bold())
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }
}
