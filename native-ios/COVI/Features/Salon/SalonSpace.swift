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
    @Query var team: [SalonStaff]
    @State private var day = Date()
    @State private var filter: String?
    @State private var booking = false
    @State private var bookingClientID: UUID?
    @State private var newClient = ""
    @State private var clientSearch = ""
    @State private var cancellingVisit: UUID?
    @State private var message = ""
    init(shop: Establishment, tab: BusinessTab, actor: UUID, role: StaffRole, pin: PINManager) {
        self.shop = shop; self.tab = tab; self.actor = actor; self.role = role; self.pin = pin
        let id = shop.id
        _visits = Query(filter: #Predicate<SalonVisit> { $0.shop == id }, sort: \.start)
        _clients = Query(filter: #Predicate<SalonClient> { $0.shop == id }, sort: \.name)
        _menu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
        _sales = Query(filter: #Predicate<SalonSaleLine> { $0.shop == id }, sort: \.date, order: .reverse)
        _team = Query(filter: #Predicate<SalonStaff> { $0.shop == id }, sort: \.name)
    }
    var admin: Bool { role == .owner || role == .manager }
    var body: some View {
        Group {
            if tab == .checkout {
                SalonCheckout(shop: shop, actor: actor, pin: pin, clients: clients, menu: menu,
                              visits: visits, team: team)
            } else {
                List {
                    if tab == .today || tab == .agenda {
                        if tab == .today {
                            let todayVisits = visits.filter { !$0.cancelled && Calendar.current.isDateInToday($0.start) }
                            let income = sales.filter { Calendar.current.isDateInToday($0.date) }
                                .reduce(Int64(0)) { $0 + $1.gross }
                            HStack(spacing: 15) {
                                Image(systemName: "calendar")
                                    .font(.largeTitle).foregroundStyle(COVITheme.sand)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(todayVisits.count) rendez-vous · Encaissé :")
                                        .font(.headline)
                                    Text(COVIMoney.text(income, currency: shop.currencyCode))
                                        .font(.title2.bold())
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: 19))
                        } else {
                            DatePicker("Jour", selection: $day, displayedComponents: .date)
                                .tint(COVITheme.navy)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 9) {
                                filterChip("Tous", name: nil)
                                ForEach(team.filter(\.active)) { person in
                                    filterChip(person.name, name: person.name)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        COVIButton(tab == .today ? "+ RDV" : "Nouveau rendez-vous", systemImage: "calendar.badge.plus") {
                            bookingClientID = nil
                            booking = true
                        }
                        .disabled(team.filter(\.active).isEmpty)
                        if team.filter(\.active).isEmpty {
                            Text("Ajoutez un collaborateur depuis Plus pour ouvrir l’agenda.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        let date = tab == .today ? Date.now : day
                        let rows = visits.filter { Calendar.current.isDate($0.start, inSameDayAs: date) && (filter == nil || $0.stylist == filter) && !$0.cancelled }
                        if rows.isEmpty { Text("Aucun rendez-vous sur cette journée.") }
                        ForEach(rows) { v in
                            Group {
                                if v.receipt == nil {
                                    NavigationLink {
                                        SalonAppointmentEditor(visit: v, shop: shop.id, actor: actor,
                                            clients: clients, menu: menu, team: team)
                                    } label: { appointmentSummary(v) }
                                } else { appointmentSummary(v) }
                            }.swipeActions {
                                if v.receipt == nil {
                                    Button("Annuler", role: .destructive) { cancellingVisit = v.id }
                                }
                            }
                        }
                    } else if tab == .clients {
                        Section("Nouveau client") {
                            TextField("Nom du client", text: $newClient)
                            Button("Créer la fiche") {
                                let name = newClient.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard (2...120).contains(name.count) else {
                                    message = "Le nom doit comporter entre 2 et 120 caractères."
                                    return
                                }
                                let client = SalonClient(shop: shop.id, name: name)
                                db.insert(client)
                                do {
                                    try BusinessOutbox.enqueue(kind: "salon.client.created",
                                        establishmentID: shop.id, entityID: client.id,
                                        actorID: actor, in: db)
                                    try SalonLedger.save(db); newClient = ""
                                } catch { db.rollback(); message = error.localizedDescription }
                            }
                        }
                        let matching = clients.filter {
                            clientSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(clientSearch) ||
                            $0.phone.localizedCaseInsensitiveContains(clientSearch)
                        }
                        if matching.isEmpty {
                            ContentUnavailableView(clients.isEmpty ? "Aucun client" : "Aucun résultat",
                                systemImage: "person.crop.circle.badge.questionmark",
                                description: Text(clients.isEmpty ? "Créez une fiche client pour réserver et encaisser." :
                                    "Essayez un autre nom ou numéro de téléphone."))
                        }
                        ForEach(matching) { c in
                            NavigationLink {
                                SalonProfile(client: c, actor: actor,
                                    history: sales.filter { $0.client == c.id && $0.service },
                                    currency: shop.currencyCode) {
                                        bookingClientID = c.id
                                        booking = true
                                    }
                            } label: {
                                COVIIconRow(symbol: "person.crop.circle", title: c.name,
                                    detail: c.phone.isEmpty ? "Fiche client" : c.phone)
                            }
                        }
                    } else if admin {
                        NavigationLink("Rapports du salon") { SalonReport(sales: sales, visits: visits,
                                                                              currency: shop.currencyCode) }
                        NavigationLink("Catalogue du salon") { SalonCatalog(shop: shop, menu: menu, actor: actor) }
                        NavigationLink("Équipe du salon") { SalonTeamSettings(shop: shop, actor: actor) }
                        if role == .owner { NavigationLink("Paramètres propriétaire") { OwnerSettings(shop: shop, pinManager: pin) } }
                    } else { Text("Salon · " + shop.name) }
                    if !message.isEmpty { Text(message) }
                }
                .modifier(SalonClientSearch(enabled: tab == .clients, text: $clientSearch))
                .listStyle(.plain)
            }
        }.navigationTitle(tab.title).scrollContentBackground(.hidden).background(COVIBackdrop())
        .sheet(isPresented: $booking) {
            SalonBooking(shop: shop.id, actor: actor, clients: clients, menu: menu,
                         team: team.filter(\.active),
                         day: tab == .today ? .now : day,
                         personID: team.first(where: { $0.name == filter && $0.active })?.id,
                         initialClient: bookingClientID)
        }
        .confirmationDialog("Annuler le rendez-vous ?", isPresented: Binding(
            get: { cancellingVisit != nil }, set: { if !$0 { cancellingVisit = nil } }
        )) {
            Button("Confirmer l’annulation", role: .destructive) {
                guard let id = cancellingVisit, let visit = visits.first(where: { $0.id == id }) else { return }
                do { try SalonLedger.cancel(shop: shop.id, actor: actor, visit: visit, db: db) }
                catch { message = error.localizedDescription }
                cancellingVisit = nil
            }
        } message: {
            Text("Cette action conserve l’historique mais libère le créneau dans l’agenda.")
        }
    }

    private func filterChip(_ title: String, name: String?) -> some View {
        Button { filter = name } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filter == name ? .white : COVITheme.navy)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(filter == name ? COVITheme.navy : .white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func appointmentSummary(_ visit: SalonVisit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(visit.start.formatted(date: .omitted, time: .shortened) + " – " +
                 visit.end.formatted(date: .omitted, time: .shortened) + " · " + visit.stylist)
                .font(.headline)
            Text((clients.first { $0.id == visit.client }?.name ?? "Client") + " · " +
                 (menu.first { $0.id == visit.service }?.title ?? "Prestation"))
            Text(visit.receipt != nil ? "Encaissé" : visit.walkIn ? "Passage spontané" : "Confirmé")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SalonClientSearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.searchable(text: $text, prompt: "Rechercher un client") }
        else { content }
    }
}

struct SalonBooking: View {
    let shop: UUID
    let actor: UUID
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let team: [SalonStaff]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var db
    @State var day: Date
    @State var personID: UUID?
    let initialClient: UUID?
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
                    ForEach(menu.filter { $0.isService && !$0.soldOut }) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Collaborateur", selection: $personID) {
                    Text("Choisir").tag(nil as UUID?)
                    ForEach(team) { person in Text(person.name).tag(Optional(person.id)) }
                }
                if !walk {
                    DatePicker("Début", selection: $day,
                               in: Date.now...Date.now.addingTimeInterval(366 * 24 * 3_600))
                }
                Text("Créneaux possibles jusqu'à un an à l'avance.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...720, step: 5)
                COVIButton("Confirmer") {
                    guard let c = clients.first(where: { $0.id == client }),
                          let p = menu.first(where: { $0.id == item }),
                          let stylist = team.first(where: { $0.id == personID }) else {
                        message = "Sélectionnez un client, une prestation et un collaborateur."; return
                    }
                    do { try SalonLedger.book(shop: shop, actor: actor, client: c, item: p, team: stylist,
                                              start: walk ? .now : day, minutes: minutes, walkIn: walk, db: db); dismiss() }
                    catch { message = error.localizedDescription }
                }
                Text(message)
            }.navigationTitle("Nouveau rendez-vous")
                .scrollContentBackground(.hidden)
                .background(COVIBackdrop())
                .toolbar { Button("Fermer") { dismiss() } }
                .onAppear {
                    if let initialClient { client = initialClient }
                    if day < Date.now.addingTimeInterval(5 * 60) {
                        day = Date.now.addingTimeInterval(15 * 60)
                    }
                }
        }
    }
}

private struct SalonAppointmentEditor: View {
    let visit: SalonVisit
    let shop: UUID
    let actor: UUID
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let team: [SalonStaff]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var db
    @State private var clientID: UUID
    @State private var serviceID: UUID
    @State private var teamID: UUID?
    @State private var start: Date
    @State private var minutes: Int
    @State private var message = ""

    init(visit: SalonVisit, shop: UUID, actor: UUID, clients: [SalonClient],
         menu: [CatalogItem], team: [SalonStaff]) {
        self.visit = visit; self.shop = shop; self.actor = actor
        self.clients = clients; self.menu = menu; self.team = team
        _clientID = State(initialValue: visit.client)
        _serviceID = State(initialValue: visit.service)
        _teamID = State(initialValue: team.first { $0.name == visit.stylist }?.id)
        _start = State(initialValue: max(visit.start, Date.now.addingTimeInterval(15 * 60)))
        _minutes = State(initialValue: max(5, min(720, Int(visit.end.timeIntervalSince(visit.start) / 60))))
    }

    var body: some View {
        Form {
            Section("Rendez-vous") {
                Picker("Client", selection: $clientID) {
                    ForEach(clients) { Text($0.name).tag($0.id) }
                }
                Picker("Prestation", selection: $serviceID) {
                    ForEach(menu.filter { $0.isService && !$0.soldOut }) { Text($0.title).tag($0.id) }
                }
                Picker("Collaborateur", selection: $teamID) {
                    Text("Choisir").tag(nil as UUID?)
                    ForEach(team.filter(\.active)) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                DatePicker("Début", selection: $start,
                           in: Date.now...Date.now.addingTimeInterval(366 * 24 * 3_600))
                Stepper("\(minutes) minutes", value: $minutes, in: 5...720, step: 5)
            }
            Section {
                Button("Enregistrer le changement") {
                    guard let client = clients.first(where: { $0.id == clientID }),
                          let service = menu.first(where: { $0.id == serviceID }),
                          let member = team.first(where: { $0.id == teamID }) else {
                        message = "Choisissez un client, une prestation et un collaborateur actif."
                        return
                    }
                    do {
                        try SalonLedger.reschedule(visit, shop: shop, actor: actor,
                            client: client, item: service, team: member,
                            start: start, minutes: minutes, db: db)
                        dismiss()
                    } catch { message = error.localizedDescription }
                }.disabled(visit.cancelled || visit.receipt != nil || team.filter(\.active).isEmpty)
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            } footer: {
                Text("Le changement libère l’ancien créneau et contrôle les disponibilités du client et du collaborateur.")
            }
        }
        .navigationTitle("Modifier le rendez-vous")
    }
}

private struct SalonProfile: View {
    let client: SalonClient
    let actor: UUID
    let history: [SalonSaleLine]
    let currency: String
    let onNewBooking: () -> Void
    @Environment(\.modelContext) private var db
    @State private var notes = ""
    @State private var name = ""
    @State private var preferences = ""
    @State private var phone = ""
    @State private var message = ""
    @State private var editing = false
    var body: some View {
        Group {
            if editing {
                Form {
                    TextField("Nom du client", text: $name).textContentType(.name)
                    TextField("Téléphone", text: $phone).keyboardType(.phonePad)
                    TextField("Préférences capillaires", text: $preferences, axis: .vertical)
                    TextField("Notes techniques", text: $notes, axis: .vertical)
                    COVIButton("Enregistrer") {
                        do {
                            try SalonLedger.updateClient(client, shop: client.shop, actor: actor,
                                name: name, phone: phone, notes: notes, preferences: preferences, db: db)
                            message = "Fiche enregistrée."
                            editing = false
                        } catch { message = error.localizedDescription }
                    }
                    if !message.isEmpty { Text(message).foregroundStyle(.red) }
                }
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        COVICard {
                            VStack(spacing: 20) {
                                HStack(spacing: 16) {
                                    Text(String(client.name.prefix(1)).uppercased())
                                        .font(.largeTitle.bold())
                                        .frame(width: 85, height: 85)
                                        .background(COVITheme.champagne, in: Circle())
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(client.name).font(.title2.bold())
                                        Label(client.phone.isEmpty ? "Téléphone non renseigné" : client.phone,
                                              systemImage: "phone")
                                            .font(.subheadline)
                                    }
                                    Spacer(minLength: 0)
                                }
                                HStack {
                                    stat("Visites", value: "\(Set(history.map(\.order)).count)")
                                    Divider()
                                    stat("Total", value: COVIMoney.text(history.reduce(0) { $0 + $1.gross }, currency: currency))
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            COVISectionTitle("Préférences & Notes techniques")
                            COVICard {
                                COVIIconRow(symbol: "list.clipboard", title: "Préférences",
                                    detail: client.preferences.isEmpty ? "Aucune préférence renseignée" : client.preferences,
                                    accessory: nil)
                                if !client.notes.isEmpty {
                                    Divider()
                                    Text(client.notes).font(.subheadline)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            COVISectionTitle("Historique des prestations (3 dernières)")
                            COVICard {
                                if history.isEmpty {
                                    Text("Aucune prestation encaissée.")
                                        .foregroundStyle(COVITheme.secondaryText)
                                }
                                ForEach(Array(history.prefix(3))) { row in
                                    if row.id != history.first?.id { Divider() }
                                    COVIIconRow(symbol: "calendar", title: row.title,
                                        detail: "\(row.date.formatted(date: .abbreviated, time: .omitted)) · \(row.stylist) · \(COVIMoney.text(row.gross, currency: currency))",
                                        accessory: nil)
                                }
                            }
                        }
                        COVIButton("Nouveau rendez-vous pour \(client.name)", systemImage: "plus") {
                            onNewBooking()
                        }
                    }
                    .foregroundStyle(COVITheme.navy)
                    .padding(18)
                }
            }
        }
        .background(COVIBackdrop())
        .navigationTitle(editing ? "Modifier la fiche" : "Fiche client")
        .toolbar {
            Button(editing ? "Annuler" : "Modifier") { editing.toggle() }
        }
        .onAppear {
            name = client.name; notes = client.notes; preferences = client.preferences; phone = client.phone
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(COVITheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
