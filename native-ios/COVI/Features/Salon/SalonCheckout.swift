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
                    ForEach(menu.filter { $0.isService == services }) { item in
                        Stepper(value: Binding(get: { basket[item.id] ?? 0 }, set: { basket[item.id] = $0 == 0 ? nil : $0 }), in: 0...999) {
                            Text("\(basket[item.id] ?? 0) × \(item.title)")
                            Text("\(item.priceMinor) FCFA").font(.caption)
                        }
                    }
                }
            }
            Picker("Règlement externe", selection: $tender) { ForEach(Tender.allCases, id: \.self) { Text($0.rawValue) } }
            COVIButton("Encaisser \(total.formatted()) FCFA") { confirm = true }
                .disabled(clientID == nil || basket.isEmpty || stylist.isEmpty)
            if let receipt {
                NavigationLink {
                    ReceiptDetail(order: receipt, shop: shop)
                } label: {
                    Label("Voir et partager le dernier reçu", systemImage: "receipt")
                }
            }
            Text(message)
        }.confirmationDialog("Confirmer la réception de \(total.formatted()) FCFA ?", isPresented: $confirm) {
            Button("Paiement reçu · " + tender.rawValue) {
                guard let client = clients.first(where: { $0.id == clientID }) else { return }
                let visit = visits.first { $0.id == visitID }
                guard visitID == nil || visit != nil else { message = SalonFault.stale.localizedDescription; return }
                do {
                    receipt = try SalonLedger.pay(shop: shop, actor: actor, pin: pin, client: client, team: stylist, visit: visit,
                                        basket: basket, menu: menu, tender: tender, db: db)
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
                TextField("Prix FCFA", text: $price).keyboardType(.numberPad)
                if !service { TextField("Stock initial", text: $qty).keyboardType(.numberPad) }
                Stepper("Commission : \(percent) %", value: $percent, in: 0...100)
                Button("Ajouter au catalogue") {
                    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, let amount = Int64(price), amount > 0,
                          let count = Int(service ? "0" : qty), count >= 0 else { message = SalonFault.invalid.localizedDescription; return }
                    let item = CatalogItem(establishmentID: shop.id, title: title, priceMinor: amount, isService: service)
                    item.stockOnHand = count; item.salonPercent = percent; db.insert(item)
                    var movementIDs: [UUID] = []
                    if count > 0 {
                        let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
                                                     delta: count, reason: "Stock initial du salon",
                                                     actorID: actor)
                        db.insert(movement)
                        movementIDs.append(movement.id)
                    }
                    do {
                        try BusinessOutbox.enqueue(kind: service ? "salon.service.created" : "salon.product.created",
                            establishmentID: shop.id, entityID: item.id,
                            actorID: actor, relatedIDs: movementIDs, in: db)
                        try SalonLedger.save(db); name = ""; price = ""; qty = ""; message = "Référence ajoutée."
                    } catch { db.rollback(); message = error.localizedDescription }
                }
            }
            ForEach(menu) { item in
                LabeledContent(item.title, value: "\(item.priceMinor) FCFA · \(item.salonPercent) %")
            }
            Text(message)
        }.navigationTitle("Catalogue salon")
    }
}

struct SalonReport: View {
    let sales: [SalonSaleLine]
    let visits: [SalonVisit]
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
                LabeledContent("CA encaissé", value: "\(gross.formatted()) FCFA")
                LabeledContent("Commissions équipe", value: "\(commissions.formatted()) FCFA")
                LabeledContent("Part salon", value: "\((gross - commissions).formatted()) FCFA")
            }
            ForEach(Array(Set(rows.map(\.stylist) + visits.map(\.stylist))).sorted(), id: \.self) { person in
                let activity = rows.filter { $0.stylist == person }
                Section(person) {
                    LabeledContent("RDV hors annulations", value: "\(visits.filter { !$0.cancelled && $0.stylist == person && includes($0.start) }.count)")
                    LabeledContent("Tickets encaissés", value: "\(Set(activity.map(\.order)).count)")
                    LabeledContent("CA", value: "\(activity.reduce(Decimal.zero) { $0 + Decimal($1.gross) }.formatted()) FCFA")
                    LabeledContent("Commission", value: "\(activity.reduce(Decimal.zero) { $0 + Decimal($1.commission) }.formatted()) FCFA")
                }
            }
        }.navigationTitle("Rapports salon")
    }
}
