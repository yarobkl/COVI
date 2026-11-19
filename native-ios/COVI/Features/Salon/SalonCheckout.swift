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
            Picker("Règlement externe", selection: $tender) { ForEach(Tender.allCases, id: \.self) { Text($0.rawValue) } }
            COVIButton("Encaisser \(total.formatted()) \(shop.currencyCode)") { confirm = true }
                .disabled(clientID == nil || basket.isEmpty || stylist.isEmpty || menu.isEmpty)
            if let receipt {
                NavigationLink {
                    ReceiptDetail(order: receipt, shop: shop)
                } label: {
                    Label("Voir et partager le dernier reçu", systemImage: "receipt")
                }
            }
            Text(message)
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
        let gross = rows.reduce(Decimal.zero) { $0 + Decimal($1.gross) }
        let commissions = rows.reduce(Decimal.zero) { $0 + Decimal($1.commission) }
        Form {
            Picker("Période", selection: $monthly) { Text("Jour").tag(false); Text("Mois").tag(true) }.pickerStyle(.segmented)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Section("Encaissements bruts") {
                LabeledContent("CA encaissé", value: "\(gross.formatted()) \(currency)")
                LabeledContent("Commissions équipe", value: "\(commissions.formatted()) \(currency)")
                LabeledContent("Part salon", value: "\((gross - commissions).formatted()) \(currency)")
            }
            ForEach(Array(Set(rows.map(\.stylist) + visits.map(\.stylist))).sorted(), id: \.self) { person in
                let activity = rows.filter { $0.stylist == person }
                Section(person) {
                    LabeledContent("RDV hors annulations", value: "\(visits.filter { !$0.cancelled && $0.stylist == person && includes($0.start) }.count)")
                    LabeledContent("Tickets encaissés", value: "\(Set(activity.map(\.order)).count)")
                    LabeledContent("CA", value: "\(activity.reduce(Decimal.zero) { $0 + Decimal($1.gross) }.formatted()) \(currency)")
                    LabeledContent("Commission", value: "\(activity.reduce(Decimal.zero) { $0 + Decimal($1.commission) }.formatted()) \(currency)")
                }
            }
        }.navigationTitle("Rapports salon")
    }
}
