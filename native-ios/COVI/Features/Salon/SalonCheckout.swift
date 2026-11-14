import SwiftUI
import SwiftData

struct SalonCheckout: View {
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let visits: [SalonVisit]
    @Environment(\.modelContext) private var db
    @State private var visitID: UUID?
    @State private var clientID: UUID?
    @State private var team = SalonTeam.chloe
    @State private var basket: [UUID:Int] = [:]
    @State private var tender = Tender.cash
    @State private var confirm = false
    @State private var message = ""
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
                    clientID = v.client; team = SalonTeam(rawValue: v.stylist) ?? .chloe; basket[v.service] = 1
                }
            }
            Picker("Client", selection: $clientID) {
                Text("Choisir").tag(nil as UUID?)
                ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
            }.disabled(visitID != nil)
            Picker("Collaborateur crédité", selection: $team) {
                ForEach(SalonTeam.allCases, id: \.self) { Text($0.rawValue) }
            }.disabled(visitID != nil)
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
            COVIButton("Encaisser \(total.formatted()) FCFA") { confirm = true }.disabled(clientID == nil || basket.isEmpty)
            Text(message)
        }.confirmationDialog("Confirmer la réception de \(total.formatted()) FCFA ?", isPresented: $confirm) {
            Button("Paiement reçu · " + tender.rawValue) {
                guard let client = clients.first(where: { $0.id == clientID }) else { return }
                let visit = visits.first { $0.id == visitID }
                guard visitID == nil || visit != nil else { message = SalonFault.stale.localizedDescription; return }
                do {
                    try SalonLedger.pay(shop: shop, actor: actor, pin: pin, client: client, team: team, visit: visit,
                                        basket: basket, menu: menu, tender: tender, db: db)
                    visitID = nil; basket = [:]; message = "Paiement enregistré."; HapticService.confirm()
                } catch { message = error.localizedDescription }
            }
        }
    }
}

struct SalonCatalog: View {
    let shop: Establishment
    let menu: [CatalogItem]
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
                    do { try SalonLedger.save(db); name = ""; price = ""; qty = ""; message = "Référence ajoutée." }
                    catch { message = error.localizedDescription }
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
            ForEach(SalonTeam.allCases, id: \.self) { person in
                let team = rows.filter { $0.stylist == person.rawValue }
                Section(person.rawValue) {
                    LabeledContent("RDV hors annulations", value: "\(visits.filter { !$0.cancelled && $0.stylist == person.rawValue && includes($0.start) }.count)")
                    LabeledContent("Tickets encaissés", value: "\(Set(team.map(\.order)).count)")
                    LabeledContent("CA", value: "\(team.reduce(Decimal.zero) { $0 + Decimal($1.gross) }.formatted()) FCFA")
                    LabeledContent("Commission", value: "\(team.reduce(Decimal.zero) { $0 + Decimal($1.commission) }.formatted()) FCFA")
                }
            }
        }.navigationTitle("Rapports salon")
    }
}
