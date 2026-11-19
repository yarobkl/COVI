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
    @State private var visitID: UUID?
    @State private var clientID: UUID?
    @State private var stylist = ""
    @State private var basket: [UUID:Int] = [:]
    @State private var tender = Tender.cash
    @State private var confirm = false
    @State private var message = ""
    @State private var receipt: CommerceOrder?
    var total: Decimal { menu.reduce(Decimal.zero) { $0 + Decimal($1.priceMinor) * Decimal(basket[$1.id] ?? 0) } }
    var body: some View {
        Form {
            Section {
                COVICard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Ticket en cours", systemImage: "person.crop.circle")
                            .font(.title3.bold())
                        if let visit = visits.first(where: { $0.id == visitID }) {
                            Text(clients.first(where: { $0.id == visit.client })?.name ?? "Client")
                                .font(.headline)
                        } else {
                            Text("Vente directe").foregroundStyle(COVITheme.secondaryText)
                        }
                    }
                }
            }
            if clients.isEmpty {
                Text("Créez d’abord une fiche dans Clients pour encaisser une prestation.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if menu.isEmpty {
                Text("Ajoutez vos prestations ou produits dans Plus → Catalogue du salon.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Picker("Ticket", selection: $visitID) {
                Text("Vente directe").tag(nil as UUID?)
                ForEach(visits.filter { !$0.cancelled && $0.receipt == nil }) { v in
                    Text((clients.first { $0.id == v.client }?.name ?? "Client") + " · " + v.start.formatted()).tag(Optional(v.id))
                }
            }.onChange(of: visitID) { _, id in
                basket = [:]
                if let v = visits.first(where: { $0.id == id }) {
                    clientID = v.client; stylist = v.stylist; basket[v.service] = 1
                }
            }
            Picker("Client", selection: $clientID) {
                Text("Choisir").tag(nil as UUID?)
                ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
            }.disabled(visitID != nil)
            Picker("Collaborateur crédité", selection: $stylist) {
                Text("Choisir").tag("")
                ForEach(team.filter { $0.active || $0.name == stylist }) { person in
                    Text(person.name).tag(person.name)
                }
            }.disabled(visitID != nil)
            if team.isEmpty {
                Text("Ajoutez votre équipe dans Plus avant d’encaisser.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach([true,false], id: \.self) { services in
                Section(services ? "Prestations" : "Produits de soin") {
                    ForEach(menu.filter { $0.isService == services &&
                        (!$0.soldOut || (visitID != nil && visits.first(where: { $0.id == visitID })?.service == $0.id)) }) { item in
                        Stepper(value: Binding(get: { basket[item.id] ?? 0 }, set: { basket[item.id] = $0 == 0 ? nil : $0 }), in: 0...999) {
                            Text("\(basket[item.id] ?? 0) × \(item.title)")
                            Text("\(item.priceMinor) \(shop.currencyCode)").font(.caption)
                        }
                    }
                }
            }
            Section("Règlement externe") {
                Picker("Moyen de paiement", selection: $tender) {
                    ForEach(Tender.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Text("Total à encaisser").font(.headline)
                    Spacer()
                    Text("\(total.formatted()) \(shop.currencyCode)")
                        .font(.headline).foregroundStyle(COVITheme.navy)
                }
            }
            Section {
                COVIButton("Encaisser \(total.formatted()) \(shop.currencyCode)") { confirm = true }
                    .disabled(clientID == nil || basket.isEmpty || stylist.isEmpty || menu.isEmpty)
            }
            if let receipt {
                NavigationLink {
                    ReceiptDetail(order: receipt, shop: shop)
                } label: {
                    Label("Voir et partager le dernier reçu", systemImage: "receipt")
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(COVITheme.navy) }
        }.confirmationDialog("Confirmer la réception de \(total.formatted()) \(shop.currencyCode) ?", isPresented: $confirm) {
            Button("Je confirme avoir reçu · " + tender.rawValue) {
                guard let client = clients.first(where: { $0.id == clientID }) else { return }
                let visit = visits.first { $0.id == visitID }
                guard visitID == nil || visit != nil else { message = SalonFault.stale.localizedDescription; return }
                do {
                    receipt = try SalonLedger.pay(shop: shop, actor: actor, pin: pin, client: client, team: stylist, visit: visit,
                                        basket: basket, menu: menu, tender: tender, confirmed: true, db: db)
                    visitID = nil; basket = [:]; message = "Paiement enregistré."; HapticService.confirm()
                } catch { message = error.localizedDescription }
            }
        }
        .onAppear {
            if stylist.isEmpty { stylist = team.first(where: \.active)?.name ?? "" }
        }
        .scrollContentBackground(.hidden)
        .background(COVIBackdrop())
    }
}

struct SalonCatalog: View {
    let shop: Establishment
    let menu: [CatalogItem]
    let actor: UUID
    @Environment(\.modelContext) private var db
    @State private var name = ""
    @State private var price = ""
    @State private var qty = ""
    @State private var percent = 0
    @State private var service = true
    @State private var message = ""
    var body: some View {
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
            Section("Catalogue actif et suspendu") {
                if menu.isEmpty {
                    ContentUnavailableView("Catalogue vide", systemImage: "list.bullet.rectangle",
                        description: Text("Ajoutez votre première prestation ou produit de soin."))
                }
                ForEach(menu) { item in
                    NavigationLink {
                        SalonCatalogEditor(shop: shop, item: item, actor: actor)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text("\(item.priceMinor) \(shop.currencyCode) · \(item.salonPercent) %" +
                                 (item.soldOut ? " · Suspendu" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(message)
        }.navigationTitle("Catalogue salon")
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
