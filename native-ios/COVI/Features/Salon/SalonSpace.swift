import SwiftUI
import SwiftData

struct SalonSpace: View {
    let shop: Establishment
    let tab: BusinessTab
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    @Environment(\.modelContext) private var db
    @Query var visits: [SalonVisit]
    @Query var clients: [SalonClient]
    @Query var menu: [CatalogItem]
    @Query var sales: [SalonSaleLine]
    @State private var day = Date()
    @State private var filter: SalonTeam?
    @State private var booking = false
    @State private var newClient = ""
    @State private var message = ""
    init(shop: Establishment, tab: BusinessTab, actor: UUID, role: StaffRole, pin: PINManager) {
        self.shop = shop; self.tab = tab; self.actor = actor; self.role = role; self.pin = pin
        let id = shop.id
        _visits = Query(filter: #Predicate<SalonVisit> { $0.shop == id }, sort: \.start)
        _clients = Query(filter: #Predicate<SalonClient> { $0.shop == id }, sort: \.name)
        _menu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
        _sales = Query(filter: #Predicate<SalonSaleLine> { $0.shop == id }, sort: \.date, order: .reverse)
    }
    var admin: Bool { role == .owner || role == .manager }
    var body: some View {
        Group {
            if tab == .checkout {
                SalonCheckout(shop: shop, actor: actor, pin: pin, clients: clients, menu: menu, visits: visits)
            } else {
                List {
                    if tab == .today || tab == .agenda {
                        if tab == .agenda { DatePicker("Jour", selection: $day, displayedComponents: .date) }
                        Picker("Collaborateur", selection: $filter) {
                            Text("Tous").tag(nil as SalonTeam?)
                            ForEach(SalonTeam.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }.pickerStyle(.segmented)
                        Button("Nouveau rendez-vous") { booking = true }
                        let date = tab == .today ? Date.now : day
                        let rows = visits.filter { Calendar.current.isDate($0.start, inSameDayAs: date) && (filter == nil || $0.stylist == filter?.rawValue) && !$0.cancelled }
                        if rows.isEmpty { Text("Aucun rendez-vous sur cette journée.") }
                        ForEach(rows) { v in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(v.start.formatted(date: .omitted, time: .shortened) + " – " + v.end.formatted(date: .omitted, time: .shortened) + " · " + v.stylist).font(.headline)
                                Text((clients.first { $0.id == v.client }?.name ?? "Client") + " · " + (menu.first { $0.id == v.service }?.title ?? "Prestation"))
                                Text(v.receipt != nil ? "Encaissé" : v.walkIn ? "Passage spontané" : "Confirmé").font(.caption)
                            }.swipeActions {
                                if v.receipt == nil { Button("Annuler", role: .destructive) {
                                    v.cancelled = true
                                    do { try SalonLedger.save(db) } catch { message = error.localizedDescription }
                                } }
                            }
                        }
                    } else if tab == .clients {
                        Section("Nouveau client") {
                            TextField("Nom du client", text: $newClient)
                            Button("Créer la fiche") {
                                let name = newClient.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                db.insert(SalonClient(shop: shop.id, name: name))
                                do { try SalonLedger.save(db); newClient = "" } catch { message = error.localizedDescription }
                            }
                        }
                        ForEach(clients) { c in NavigationLink(c.name) { SalonProfile(client: c, history: sales.filter { $0.client == c.id && $0.service }) } }
                    } else if admin {
                        NavigationLink("Rapports du salon") { SalonReport(sales: sales, visits: visits) }
                        NavigationLink("Catalogue du salon") { SalonCatalog(shop: shop, menu: menu) }
                        if role == .owner { NavigationLink("Paramètres propriétaire") { OwnerSettings(shop: shop, pinManager: pin) } }
                    } else { Text("Salon · " + shop.name) }
                    if !message.isEmpty { Text(message) }
                }
            }
        }.navigationTitle(tab.title).scrollContentBackground(.hidden).background(COVITheme.cream)
        .sheet(isPresented: $booking) { SalonBooking(shop: shop.id, clients: clients, menu: menu, day: tab == .today ? .now : day, team: filter ?? .chloe) }
    }
}

struct SalonBooking: View {
    let shop: UUID
    let clients: [SalonClient]
    let menu: [CatalogItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var db
    @State var day: Date
    @State var team: SalonTeam
    @State private var client: UUID?
    @State private var item: UUID?
    @State private var walk = false
    @State private var minutes = 30
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Accueil", selection: $walk) { Text("Sur rendez-vous").tag(false); Text("Passage spontané").tag(true) }.pickerStyle(.segmented)
                Picker("Client", selection: $client) {
                    Text("Choisir").tag(nil as UUID?)
                    ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Prestation", selection: $item) {
                    Text("Choisir").tag(nil as UUID?)
                    ForEach(menu.filter(\.isService)) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Collaborateur", selection: $team) { ForEach(SalonTeam.allCases, id: \.self) { Text($0.rawValue) } }
                if !walk { DatePicker("Début", selection: $day) }
                Stepper("\(minutes) minutes", value: $minutes, in: 5...720, step: 5)
                COVIButton("Confirmer") {
                    guard let c = clients.first(where: { $0.id == client }), let p = menu.first(where: { $0.id == item }) else { message = "Sélectionnez un client et une prestation."; return }
                    do { try SalonLedger.book(shop: shop, client: c, item: p, team: team, start: walk ? .now : day, minutes: minutes, walkIn: walk, db: db); dismiss() }
                    catch { message = error.localizedDescription }
                }
                Text(message)
            }.navigationTitle("Nouveau rendez-vous").toolbar { Button("Fermer") { dismiss() } }
        }
    }
}

private struct SalonProfile: View {
    let client: SalonClient
    let history: [SalonSaleLine]
    @Environment(\.modelContext) private var db
    @State private var notes = ""
    @State private var preferences = ""
    @State private var phone = ""
    @State private var message = ""
    var body: some View {
        Form {
            TextField("Téléphone", text: $phone).keyboardType(.phonePad)
            TextField("Préférences capillaires", text: $preferences, axis: .vertical)
            TextField("Notes techniques", text: $notes, axis: .vertical)
            Button("Enregistrer") {
                client.phone = phone; client.notes = notes; client.preferences = preferences
                do { try SalonLedger.save(db); message = "Fiche enregistrée." } catch { message = error.localizedDescription }
            }
            Section("Trois dernières prestations") {
                ForEach(history.prefix(3)) { row in
                    Text(row.title + " · " + row.stylist)
                    Text(row.date.formatted() + " · \(row.gross) FCFA").font(.caption)
                }
            }
            Text(message)
        }.navigationTitle(client.name).onAppear { notes = client.notes; preferences = client.preferences; phone = client.phone }
    }
}
