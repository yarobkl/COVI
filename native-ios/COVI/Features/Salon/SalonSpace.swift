import SwiftUI
import SwiftData
import Combine

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
    @State private var now = Date()
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var filter: String?
    @State private var booking = false
    @State private var bookingClientID: UUID?
    @State private var newClient = ""
    @State private var addingClient = false
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
    private var activeTeam: [SalonStaff] { team.filter(\.active) }
    private var selectedStylist: SalonStaff? { activeTeam.first { $0.name == filter } }
    private var overviewDate: Date {
#if DEBUG && targetEnvironment(simulator)
        if let date = diagnostics?.salonClock { return date }
#endif
        return now
    }
    var body: some View {
        Group {
            if tab == .checkout {
                SalonCheckout(shop: shop, actor: actor, pin: pin, clients: clients, menu: menu,
                              visits: visits, team: team)
            } else {
                List {
                    if tab == .today {
                        todaySections
                    } else if tab == .agenda {
                        agendaSections
                    } else if tab == .clients {
                        Section {
                            COVISectionTitle("Clients (\(clients.count))")
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
        .toolbar {
            if tab == .today || tab == .agenda {
                Button {
                    bookingClientID = nil
                    booking = true
                } label: {
                    if tab == .today {
                        Label("RDV", systemImage: "plus").labelStyle(.titleAndIcon)
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .accessibilityLabel("Nouveau rendez-vous")
                .buttonStyle(.borderedProminent)
                .tint(COVITheme.navy)
                .disabled(activeTeam.isEmpty)
            }
            if tab == .clients {
                Button("Client", systemImage: "plus") { addingClient = true }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { current in
            if tab == .today { now = current }
        }
        .sheet(isPresented: $addingClient) {
            NavigationStack {
                Form {
                    Section("Nouveau client") {
                        TextField("Nom du client", text: $newClient)
                            .textContentType(.name)
                        COVIButton("Créer la fiche") { createClient() }
                            .disabled(newClient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !message.isEmpty { Text(message).foregroundStyle(.red) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(COVIBackdrop())
                .navigationTitle("Ajouter un client")
                .toolbar { Button("Fermer") { addingClient = false } }
            }
        }
        .sheet(isPresented: $booking) {
            SalonBooking(shop: shop.id, actor: actor, currency: shop.currencyCode, clients: clients, menu: menu,
                         team: activeTeam, visits: visits,
                         day: tab == .today ? .now : day,
                         personID: selectedStylist?.id,
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

    @ViewBuilder private var todaySections: some View {
        let date = overviewDate
        let appointments = visits.filter {
            !$0.cancelled && Calendar.current.isDate($0.start, inSameDayAs: date)
        }
        let walkIns = appointments.filter { $0.walkIn && $0.receipt == nil }
        let upcoming = appointments.filter { !$0.walkIn && $0.receipt == nil && $0.start >= date }
        let history = appointments.filter {
            $0.receipt != nil || (!$0.walkIn && $0.start < date)
        }

        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.title2).foregroundStyle(COVITheme.sand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appointments.count) rendez-vous").font(.headline)
                if admin {
                    let income = sales.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                        .reduce(Int64(0)) { $0 + $1.gross }
                    Text("Encaissé · \(COVIMoney.text(income, currency: shop.currencyCode))")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if activeTeam.isEmpty { missingTeam }
        if appointments.isEmpty {
            Text("Aucun rendez-vous aujourd’hui.")
                .foregroundStyle(COVITheme.secondaryText)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        appointmentSection("Passages spontanés", visits: walkIns)
        appointmentSection("Prochains rendez-vous", visits: upcoming)
        appointmentSection("Autres rendez-vous du jour", visits: history)
    }

    @ViewBuilder private var agendaSections: some View {
        DatePicker("Jour", selection: $day, displayedComponents: .date)
            .tint(COVITheme.navy)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        if activeTeam.isEmpty {
            missingTeam
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    filterChip("Tous (\(activeTeam.count))", name: nil)
                    ForEach(activeTeam) { person in
                        filterChip(person.name, name: person.name)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            SalonAgendaTimeline(day: day, team: activeTeam, stylist: selectedStylist?.name,
                visits: visits, clients: clients, menu: menu, shop: shop.id, actor: actor)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var missingTeam: some View {
        Text("Ajoutez un collaborateur depuis Plus pour ouvrir l’agenda.")
            .font(.footnote)
            .foregroundStyle(COVITheme.secondaryText)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder private func appointmentSection(_ title: String, visits: [SalonVisit]) -> some View {
        if !visits.isEmpty {
            Section {
                ForEach(visits) { visit in
                    Group {
                        if visit.receipt == nil {
                            NavigationLink {
                                SalonAppointmentEditor(visit: visit, shop: shop.id, actor: actor,
                                    clients: clients, menu: menu, team: team)
                            } label: { appointmentSummary(visit) }
                        } else {
                            appointmentSummary(visit)
                        }
                    }
                    .listRowBackground(Color.white)
                    .swipeActions {
                        if visit.receipt == nil {
                            Button("Annuler", role: .destructive) { cancellingVisit = visit.id }
                        }
                    }
                }
            } header: {
                COVISectionTitle(title)
            }
        }
    }

    private func filterChip(_ title: String, name: String?) -> some View {
        Button { filter = name } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedStylist?.name == name ? .white : COVITheme.navy)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(selectedStylist?.name == name ? COVITheme.navy : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedStylist?.name == name ? .isSelected : [])
    }

    private func createClient() {
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
            try SalonLedger.save(db)
            newClient = ""; message = ""; addingClient = false
            HapticService.confirm()
        } catch {
            db.rollback()
            message = error.localizedDescription
        }
    }

    private func appointmentSummary(_ visit: SalonVisit) -> some View {
        let name = clients.first { $0.id == visit.client }?.name ?? "Client"
        let service = menu.first { $0.id == visit.service }?.title ?? "Prestation"
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: visit.walkIn ? "scissors" : "calendar")
                .font(.body)
                .frame(width: 38, height: 38)
                .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline.bold())
                Text(service).font(.subheadline)
                Text("\(visit.stylist) · " + visit.start.formatted(date: .omitted, time: .shortened) +
                     " – " + visit.end.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(COVITheme.secondaryText)
                Text(visit.receipt != nil ? "Encaissé" : visit.walkIn ? "Arrivé" : "Confirmé")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(visit.walkIn && visit.receipt == nil ? COVITheme.warning : COVITheme.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(visit.walkIn && visit.receipt == nil ? COVITheme.warningTint : COVITheme.successTint,
                                in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(COVITheme.navy)
        .accessibilityElement(children: .combine)
    }
}

private struct SalonAgendaTimeline: View {
    let day: Date
    let team: [SalonStaff]
    let stylist: String?
    let visits: [SalonVisit]
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let shop: UUID
    let actor: UUID
    private let firstHour = 8
    private let lastHour = 21
    private let halfHourHeight: CGFloat = 47
    private var slots: Int { (lastHour - firstHour) * 2 }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 0) {
                    Text("Heure")
                        .font(.caption).frame(height: 56)
                    ForEach(0..<slots, id: \.self) { step in
                        Text(String(format: "%02d:%02d", firstHour + step / 2, step.isMultiple(of: 2) ? 0 : 30))
                            .font(.caption2).foregroundStyle(COVITheme.secondaryText)
                            .frame(width: 52, height: halfHourHeight, alignment: .top)
                    }
                }
                ForEach(team.filter { stylist == nil || $0.name == stylist }) { person in
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "scissors")
                            Text(person.name).font(.headline).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 15))
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(0..<slots, id: \.self) { _ in
                                    Rectangle().fill(.clear)
                                        .frame(height: halfHourHeight)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(COVITheme.separator).frame(height: 1)
                                        }
                                }
                            }
                            ForEach(visits.filter {
                                !$0.cancelled && $0.stylist == person.name &&
                                Calendar.current.isDate($0.start, inSameDayAs: day)
                            }) { visit in
                                if visit.receipt == nil {
                                    NavigationLink {
                                        SalonAppointmentEditor(visit: visit, shop: shop, actor: actor,
                                            clients: clients, menu: menu, team: team)
                                    } label: { appointmentTile(visit) }
                                        .buttonStyle(.plain)
                                        .offset(y: position(visit.start))
                                } else {
                                    appointmentTile(visit).offset(y: position(visit.start))
                                }
                            }
                        }
                        .frame(width: 162, height: CGFloat(slots) * halfHourHeight, alignment: .top)
                        .background(.white.opacity(0.5))
                    }
                    .frame(width: 162)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(12)
        }
        .frame(height: 600)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }

    private func position(_ date: Date) -> CGFloat {
        let units = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (units.hour ?? 0) * 60 + (units.minute ?? 0) - firstHour * 60
        return max(0, CGFloat(minutes) / 30 * halfHourHeight)
    }

    private func appointmentTile(_ visit: SalonVisit) -> some View {
        let duration = visit.end.timeIntervalSince(visit.start)
        let color = visit.receipt != nil ? COVITheme.successTint : visit.walkIn ? COVITheme.champagne : Color(red: 0.82, green: 0.90, blue: 1)
        return VStack(alignment: .leading, spacing: 5) {
            Text(visit.start.formatted(date: .omitted, time: .shortened) + " – " +
                 visit.end.formatted(date: .omitted, time: .shortened))
                .font(.caption.bold())
            Text(clients.first(where: { $0.id == visit.client })?.name ?? "Client")
                .font(.subheadline.bold()).lineLimit(1)
            Text(menu.first(where: { $0.id == visit.service })?.title ?? "Prestation")
                .font(.caption).lineLimit(2)
            Text(visit.receipt != nil ? "Encaissé" : visit.walkIn ? "Arrivé" : "Confirmé")
                .font(.caption2.weight(.semibold))
        }
        .frame(width: 140, height: max(70, CGFloat(duration / 1_800) * halfHourHeight - 8), alignment: .topLeading)
        .padding(8)
        .background(color, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(COVITheme.navy.opacity(0.12)))
        .padding(.horizontal, 3)
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
    let currency: String
    let clients: [SalonClient]
    let menu: [CatalogItem]
    let team: [SalonStaff]
    let visits: [SalonVisit]
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
    private var chosenClient: SalonClient? { clients.first { $0.id == client } }
    private var chosenItem: CatalogItem? { menu.first { $0.id == item } }
    private var chosenStylist: SalonStaff? { team.first { $0.id == personID } }
    private var chosenStart: Date { walk ? .now : day }
    private var slotAvailable: Bool? {
        guard let chosenClient, let chosenStylist else { return nil }
        let start = chosenStart
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return !visits.contains {
            !$0.cancelled && $0.shop == shop &&
            ($0.client == chosenClient.id || $0.stylist == chosenStylist.name) &&
            $0.start < end && $0.end > start
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    HStack(spacing: 0) {
                        forEachArrival(false, label: "Rendez-vous prévu")
                        forEachArrival(true, label: "Passage spontané")
                    }
                    .padding(4)
                    .background(.white, in: Capsule())
                    COVICard {
                        VStack(spacing: 17) {
                            HStack(spacing: 12) {
                                bookingIcon("person")
                                Picker("Client", selection: $client) {
                                    Text("Choisir un client").tag(nil as UUID?)
                                    ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
                                }
                                .tint(COVITheme.navy)
                            }
                            Divider()
                            HStack(spacing: 12) {
                                bookingIcon("scissors")
                                Picker("Prestation", selection: $item) {
                                    Text("Choisir une prestation").tag(nil as UUID?)
                                    ForEach(menu.filter { $0.isService && !$0.soldOut }) {
                                        Text("\($0.title) · \(COVIMoney.text($0.priceMinor, currency: currency))")
                                            .tag(Optional($0.id))
                                    }
                                }
                                .tint(COVITheme.navy)
                            }
                            Divider()
                            HStack(spacing: 12) {
                                bookingIcon("person.2")
                                Picker("Collaborateur", selection: $personID) {
                                    Text("Choisir un collaborateur").tag(nil as UUID?)
                                    ForEach(team) { person in Text(person.name).tag(Optional(person.id)) }
                                }
                                .tint(COVITheme.navy)
                            }
                            Divider()
                            HStack(spacing: 12) {
                                bookingIcon("calendar")
                                if walk {
                                    LabeledContent("Créneau", value: "Maintenant")
                                } else {
                                    DatePicker("Créneau", selection: $day,
                                        in: Date.now...Date.now.addingTimeInterval(366 * 24 * 3_600))
                                        .tint(COVITheme.navy)
                                }
                            }
                            Divider()
                            Stepper("Durée : \(minutes) minutes", value: $minutes, in: 5...720, step: 5)
                                .tint(COVITheme.navy)
                            if let slotAvailable {
                                COVIBadge(title: slotAvailable ? "Créneau libre (sans chevauchement)" :
                                        "Créneau indisponible", tint: slotAvailable ? COVITheme.successTint : COVITheme.dangerTint,
                                        foreground: slotAvailable ? COVITheme.success : .red)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .foregroundStyle(COVITheme.navy)
                    }
                    if !message.isEmpty { Text(message).foregroundStyle(.red).font(.footnote) }
                }
                .padding(18)
            }
            .background(COVIBackdrop())
            .navigationTitle("Nouveau rendez-vous")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                COVIButton("Confirmer le rendez-vous") { saveBooking() }
                    .disabled(chosenClient == nil || chosenItem == nil || chosenStylist == nil || slotAvailable == false)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(COVITheme.cream)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { saveBooking() }
                        .disabled(chosenClient == nil || chosenItem == nil || chosenStylist == nil || slotAvailable == false)
                }
            }
            .onAppear {
                if let initialClient { client = initialClient }
                if day < Date.now.addingTimeInterval(5 * 60) {
                    day = Date.now.addingTimeInterval(15 * 60)
                }
            }
        }
    }

    private func forEachArrival(_ spontaneous: Bool, label: String) -> some View {
        Button { walk = spontaneous } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(walk == spontaneous ? .white : COVITheme.navy)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(walk == spontaneous ? COVITheme.navy : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func bookingIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3).foregroundStyle(COVITheme.navy)
            .frame(width: 46, height: 46)
            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 13))
    }

    private func saveBooking() {
        guard let c = chosenClient, let p = chosenItem, let stylist = chosenStylist else {
            message = "Sélectionnez un client, une prestation et un collaborateur."
            return
        }
        do {
            try SalonLedger.book(shop: shop, actor: actor, client: c, item: p, team: stylist,
                                 start: chosenStart, minutes: minutes, walkIn: walk, db: db)
            dismiss()
        } catch { message = error.localizedDescription }
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
