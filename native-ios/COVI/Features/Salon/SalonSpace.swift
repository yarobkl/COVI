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
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var textSize
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
    @State private var showsAgendaGrid = false
    @State private var choosingAgendaDate = false
    @State private var booking = false
    @State private var bookingClientID: UUID?
    @State private var newClient = ""
    @State private var addingClient = false
    @State private var clientSearch = ""
    @State private var directoryFilter = SalonDirectoryFilter.all
    @State private var clientProfileID: UUID?
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
                        clientSections
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
                .safeAreaInset(edge: .bottom) {
                    if tab == .agenda && !textSize.isAccessibilitySize {
                        COVIButton("Nouveau rendez-vous", systemImage: "plus.circle", action: startAgendaBooking)
                        .disabled(activeTeam.isEmpty)
                        .padding(.horizontal, COVITheme.Metrics.screenPadding)
                        .padding(.vertical, 8)
                        .background(COVITheme.cream)
                    }
                }
            }
        }.navigationTitle(tab.title).scrollContentBackground(.hidden).background(COVIBackdrop())
        .toolbar {
            if tab == .today {
                Button {
                    bookingClientID = nil
                    booking = true
                } label: {
                    Label("RDV", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Nouveau rendez-vous")
                .buttonStyle(.borderedProminent)
                .tint(COVITheme.navy)
                .disabled(activeTeam.isEmpty)
            }
            if tab == .agenda {
                Button { showsAgendaGrid.toggle() } label: {
                    Image(systemName: showsAgendaGrid ? "list.bullet" : "rectangle.split.3x1")
                }
                .accessibilityLabel(showsAgendaGrid ? "Afficher la liste du jour" : "Afficher le planning par collaborateur")
                if textSize.isAccessibilitySize {
                    Button(action: startAgendaBooking) {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Nouveau rendez-vous")
                    .disabled(activeTeam.isEmpty)
                }
            }
            if tab == .clients {
                Button("Client", systemImage: "plus") { addingClient = true }
                    .buttonStyle(.borderedProminent)
                    .tint(COVITheme.navy)
            }
        }
        .navigationDestination(item: $clientProfileID) { id in
            if let client = clients.first(where: { $0.id == id }) {
                SalonProfile(client: client, actor: actor,
                    history: sales.filter { $0.client == id && $0.service },
                    currency: shop.currencyCode) {
                        bookingClientID = id
                        booking = true
                    }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { current in
            if tab == .today || tab == .clients { now = current }
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
#if DEBUG && targetEnvironment(simulator)
        .task {
            if tab == .agenda, diagnostics?.salonBooking != nil { booking = true }
            if tab == .agenda, diagnostics?.scenario == .salonAgendaGrid { showsAgendaGrid = true }
            if tab == .clients, diagnostics?.scenario == .salonClientsUpcoming { directoryFilter = .upcoming }
            if tab == .clients, let id = diagnostics?.salonProfileID { clientProfileID = id }
        }
#endif
        .sheet(isPresented: $booking) {
            bookingSheet.presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $choosingAgendaDate) {
            NavigationStack {
                ScrollView {
                    DatePicker("Choisir une date", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                }
                .navigationTitle("Date de l’agenda")
                .navigationBarTitleDisplayMode(.inline)
                .tint(COVITheme.navy)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { choosingAgendaDate = false }
                    }
                }
            }
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

    @ViewBuilder private var clientSections: some View {
        let query = clientSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneDigits = query.filter(\.isNumber)
        let isPhoneQuery = !phoneDigits.isEmpty && query.allSatisfy { $0.isNumber || " +()-.".contains($0) }
        let historyByClient = Dictionary(grouping: sales.filter(\.service), by: \.client)
        let visitCounts = historyByClient.mapValues { Set($0.map(\.order)).count }
        let upcomingByClient = Dictionary(grouping: visits.filter {
            !$0.cancelled && $0.receipt == nil && !$0.walkIn && $0.start >= now
        }, by: \.client)
        let matching = clients.filter { client in
            let matchesSearch = query.isEmpty || client.name.localizedCaseInsensitiveContains(query) ||
                (isPhoneQuery && client.phone.filter(\.isNumber).contains(phoneDigits)) ||
                client.phone.localizedCaseInsensitiveContains(query)
            return matchesSearch && directoryFilter.includes(visits: visitCounts[client.id, default: 0],
                hasUpcoming: upcomingByClient[client.id] != nil)
        }

        if !clients.isEmpty {
            directoryFilters
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if matching.isEmpty {
            ContentUnavailableView(clients.isEmpty ? "Aucun client" : "Aucun résultat",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text(clients.isEmpty ? "Créez une fiche client pour réserver et encaisser." :
                    "Modifiez le filtre ou la recherche."))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(matching) { client in
                    let history = historyByClient[client.id] ?? []
                    let count = visitCounts[client.id, default: 0]
                    let nextVisit = upcomingByClient[client.id]?.first
                    Button {
                        clientProfileID = client.id
                    } label: {
                        clientRow(client, visitCount: count, latestService: history.first, nextVisit: nextVisit)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 17, bottom: 3, trailing: 17))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    private var directoryFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SalonDirectoryFilter.allCases) { option in
                    let selected = option == directoryFilter
                    Button { directoryFilter = option } label: {
                        Text(option == .all ? "Tous (\(clients.count))" : option.rawValue)
                            .font(.caption.weight(.semibold))
                            .fixedSize()
                            .padding(.horizontal, 9)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? .white : COVITheme.navy)
                            .background(selected ? COVITheme.navy : COVITheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtrer les clients")
    }

    private func clientRow(_ client: SalonClient, visitCount: Int,
                           latestService: SalonSaleLine?, nextVisit: SalonVisit?) -> some View {
        HStack(spacing: 10) {
            SalonClientInitials(name: client.name,
                tint: nextVisit != nil ? COVITheme.successTint : visitCount > 0 ? COVITheme.champagne : COVITheme.blue.opacity(0.10))
            VStack(alignment: .leading, spacing: 4) {
                Text(client.name).font(.subheadline.bold())
                if !client.phone.isEmpty {
                    Text(client.phone)
                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                }
                if let nextVisit {
                    Text("RDV · " + nextVisit.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                } else if let latestService {
                    Text("Dernière prestation · " + latestService.title)
                        .font(.caption).foregroundStyle(COVITheme.secondaryText)
                }
                if textSize.isAccessibilitySize && visitCount > 0 {
                    visitCountLabel(visitCount)
                }
            }
            Spacer(minLength: 4)
            if !textSize.isAccessibilitySize && visitCount > 0 {
                visitCountLabel(visitCount)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(COVITheme.navy)
        .frame(minHeight: 48)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(COVITheme.card, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func visitCountLabel(_ count: Int) -> some View {
        Text(count == 1 ? "1 visite" : "\(count) visites")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(COVITheme.champagne, in: Capsule())
    }

    @ViewBuilder private var bookingSheet: some View {
#if DEBUG && targetEnvironment(simulator)
        if let diagnostics, let sample = diagnostics.salonBooking {
            SalonBooking(shop: shop.id, actor: actor, currency: shop.currencyCode,
                clients: clients, menu: menu, team: activeTeam, visits: visits,
                day: sample.start, personID: sample.stylistID, initialClient: sample.clientID,
                initialItem: sample.serviceID, initialMinutes: 120)
                .task { await diagnostics.signalAfterPresentation() }
        } else {
            liveBooking
        }
#else
        liveBooking
#endif
    }

    private var liveBooking: some View {
        SalonBooking(shop: shop.id, actor: actor, currency: shop.currencyCode,
            clients: clients, menu: menu, team: activeTeam, visits: visits,
            day: tab == .agenda ? agendaBookingDate : .now,
            personID: showsAgendaGrid ? selectedStylist?.id : nil,
            initialClient: bookingClientID)
    }

    private var agendaBookingDate: Date {
        if calendar.isDateInToday(day) { return .now }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private func startAgendaBooking() {
        bookingClientID = nil
        booking = true
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
        SalonAgendaWeek(selectedDay: $day)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        HStack {
            agendaDayTitle
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            agendaDatePicker
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if activeTeam.isEmpty { missingTeam }
        if showsAgendaGrid && !activeTeam.isEmpty {
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
        } else {
            let appointments = visits.filter {
                !$0.cancelled && calendar.isDate($0.start, inSameDayAs: day)
            }
            if appointments.isEmpty {
                ContentUnavailableView("Aucun rendez-vous ce jour", systemImage: "calendar")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(appointments) { visit in
                Group {
                    if visit.receipt == nil {
                        NavigationLink {
                            SalonAppointmentEditor(visit: visit, shop: shop.id, actor: actor,
                                clients: clients, menu: menu, team: activeTeam)
                        } label: { agendaAppointment(visit) }
                    } else {
                        agendaAppointment(visit)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var agendaDayTitle: some View {
        let title = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return Text(title.prefix(1).uppercased() + String(title.dropFirst()))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private var agendaDatePicker: some View {
        Button { choosingAgendaDate = true } label: {
            Image(systemName: "calendar")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choisir une date")
    }

    private func agendaAppointment(_ visit: SalonVisit) -> some View {
        let client = clients.first { $0.id == visit.client }?.name ?? "Client"
        let service = menu.first { $0.id == visit.service }?.title ?? "Prestation"
        let status = visit.receipt != nil ? "Encaissé" : visit.walkIn ? "Arrivé" : "Confirmé"
        let accent = visit.receipt != nil ? COVITheme.success : visit.walkIn ? COVITheme.warning : COVITheme.blue
        return SalonAgendaAppointmentRow(start: visit.start, end: visit.end, title: "\(service) · \(client)",
            stylist: visit.stylist, status: status, accent: accent)
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

private struct SalonAgendaWeek: View {
    @Binding var selectedDay: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let first = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start
            ?? calendar.startOfDay(for: selectedDay)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    dayButton(day)
                }
            }
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayButton(day).id(day)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { scroll.scrollTo(calendar.startOfDay(for: selectedDay), anchor: .center) }
                .onChange(of: selectedDay) { _, day in
                    scroll.scrollTo(calendar.startOfDay(for: day), anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jours de la semaine")
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
        return Button { selectedDay = day } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(.semibold))
            }
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .frame(minWidth: textSize.isAccessibilitySize ? 64 : 34, maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? .white : COVITheme.navy)
            .background(selected ? COVITheme.navy : COVITheme.card, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SalonAgendaAppointmentRow: View {
    let start: Date
    let end: Date
    let title: String
    let stylist: String
    let status: String
    let accent: Color
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 9))
        layout {
            if !textSize.isAccessibilitySize {
                Text(start, style: .time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(COVITheme.secondaryText)
                    .padding(.top, 9)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(start.formatted(date: .omitted, time: .shortened) + " – " +
                     end.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(COVITheme.secondaryText)
                Text("\(stylist) · \(status)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(COVITheme.navy)
            }
            .padding(.vertical, 9)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(accent.opacity(0.11))
            .overlay(alignment: .leading) {
                Rectangle().fill(accent).frame(width: 3).accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
        if enabled { content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nom ou numéro") }
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
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.modelContext) private var db
    @State private var day: Date
    @State private var personID: UUID?
    @State private var client: UUID?
    @State private var item: UUID?
    @State private var walk = false
    @State private var minutes: Int
    @State private var editingSlot = false
    @State private var message = ""

    init(shop: UUID, actor: UUID, currency: String, clients: [SalonClient], menu: [CatalogItem],
         team: [SalonStaff], visits: [SalonVisit], day: Date, personID: UUID?, initialClient: UUID?,
         initialItem: UUID? = nil, initialMinutes: Int = 30) {
        self.shop = shop
        self.actor = actor
        self.currency = currency
        self.clients = clients
        self.menu = menu
        self.team = team
        self.visits = visits
        let now = Date.now
        _day = State(initialValue: day < now.addingTimeInterval(5 * 60) ? now.addingTimeInterval(15 * 60) : day)
        _personID = State(initialValue: personID)
        _client = State(initialValue: initialClient)
        _item = State(initialValue: initialItem)
        _minutes = State(initialValue: initialMinutes)
    }

    private var offeredServices: [CatalogItem] { menu.filter { $0.isService && !$0.soldOut } }
    private var chosenClient: SalonClient? { clients.first { $0.id == client } }
    private var chosenItem: CatalogItem? { offeredServices.first { $0.id == item } }
    private var chosenStylist: SalonStaff? { team.first { $0.id == personID && $0.active } }
    private var chosenStart: Date { walk ? .now : day }
    private var bookingWindow: ClosedRange<Date> {
        let now = Date.now
        return now...now.addingTimeInterval(366 * 24 * 3_600)
    }
    private var slotAvailable: Bool? {
        guard let chosenClient, chosenItem != nil, let chosenStylist else { return nil }
        let start = chosenStart
        let window = bookingWindow
        guard start >= window.lowerBound.addingTimeInterval(-60), start <= window.upperBound else { return false }
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return !visits.contains {
            !$0.cancelled && $0.shop == shop &&
            ($0.client == chosenClient.id || $0.stylist == chosenStylist.name) &&
            $0.start < end && $0.end > start
        }
    }

    private var slotSummary: String {
        if walk { return "Maintenant · \(minutes) min" }
        let end = day.addingTimeInterval(TimeInterval(minutes * 60))
        let endDate: Date.FormatStyle.DateStyle = Calendar.current.isDate(day, inSameDayAs: end) ? .omitted : .abbreviated
        return day.formatted(date: .abbreviated, time: .shortened) + " – " +
            end.formatted(date: endDate, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let arrivalLayout = textSize.isAccessibilitySize ?
                        AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
                    arrivalLayout {
                        arrivalMode("Rendez-vous prévu", spontaneous: false)
                        arrivalMode("Passage spontané", spontaneous: true)
                    }
                    .padding(3)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Type de rendez-vous")

                    COVICard {
                        VStack(spacing: 8) {
                            Menu {
                                Picker("Client", selection: $client) {
                                    Text("Choisir un client").tag(nil as UUID?)
                                    ForEach(clients) { Text($0.name).tag(Optional($0.id)) }
                                }
                            } label: {
                                bookingRow("Client", symbol: "person", detail: chosenClient?.name ?? "Choisir un client",
                                    extra: chosenClient.flatMap { $0.phone.isEmpty ? nil : $0.phone }, showsChevron: true)
                            }
                            Divider()
                            Menu {
                                Picker("Prestation", selection: $item) {
                                    Text("Choisir une prestation").tag(nil as UUID?)
                                    ForEach(offeredServices) { service in
                                        Text("\(service.title) · \(COVIMoney.text(service.priceMinor, currency: currency))")
                                            .tag(Optional(service.id))
                                    }
                                }
                            } label: {
                                bookingRow("Prestation", symbol: "scissors",
                                    detail: chosenItem?.title ?? "Choisir une prestation",
                                    extra: chosenItem.map { COVIMoney.text($0.priceMinor, currency: currency) }, showsChevron: true)
                            }
                            Divider()
                            Menu {
                                Picker("Collaborateur", selection: $personID) {
                                    Text("Choisir un collaborateur").tag(nil as UUID?)
                                    ForEach(team) { person in Text(person.name).tag(Optional(person.id)) }
                                }
                            } label: {
                                bookingRow("Collaborateur", symbol: "person.2",
                                    detail: chosenStylist?.name ?? "Choisir un collaborateur", showsChevron: true)
                            }
                            Divider()
                            DisclosureGroup(isExpanded: $editingSlot) {
                                VStack(spacing: 10) {
                                    if !walk {
                                        DatePicker("Date et heure", selection: $day, in: bookingWindow)
                                    }
                                    Stepper("Durée : \(minutes) min", value: $minutes, in: 5...720, step: 5)
                                }
                                .padding(.vertical, 8)
                            } label: {
                                bookingRow("Créneau", symbol: "calendar", detail: slotSummary)
                            }

                            if let slotAvailable {
                                Label(slotAvailable ? "Créneau libre (sans chevauchement)" : "Créneau indisponible",
                                    systemImage: slotAvailable ? "checkmark" : "exclamationmark.circle")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(slotAvailable ? COVITheme.success : .red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(slotAvailable ? COVITheme.successTint : COVITheme.dangerTint,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .foregroundStyle(COVITheme.navy)
                        .tint(COVITheme.navy)
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
                    .disabled(slotAvailable != true)
                    .opacity(slotAvailable == true ? 1 : 0.45)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(COVITheme.cream)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { saveBooking() }
                        .disabled(slotAvailable != true)
                }
            }
        }
    }

    private func arrivalMode(_ title: String, spontaneous: Bool) -> some View {
        let selected = walk == spontaneous
        return Button {
            walk = spontaneous
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? .white : COVITheme.navy)
                .background(selected ? COVITheme.navy : .clear, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bookingRow(_ title: String, symbol: String, detail: String, extra: String? = nil,
                            showsChevron: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 41, height: 41)
                .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.subheadline)
                if let extra {
                    Text(extra)
                        .font(.caption)
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(COVITheme.navy)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

enum SalonDirectoryFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case visited = "Avec visites"
    case unvisited = "Sans visite"
    case upcoming = "RDV à venir"

    var id: Self { self }

    func includes(visits: Int, hasUpcoming: Bool) -> Bool {
        switch self {
        case .all: true
        case .visited: visits > 0
        case .unvisited: visits == 0
        case .upcoming: hasUpcoming
        }
    }
}

private struct SalonClientInitials: View {
    let name: String
    var large = false
    var tint: Color = COVITheme.champagne

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        return [words.first?.first, words.count > 1 ? words.last?.first : nil]
            .compactMap { $0 }.map { String($0) }.joined().uppercased()
    }

    var body: some View {
        Text(initials)
            .font(large ? .title2.bold() : .subheadline.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: large ? 68 : 40, height: large ? 68 : 40)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct SalonProfile: View {
    let client: SalonClient
    let actor: UUID
    let history: [SalonSaleLine]
    let currency: String
    let onNewBooking: () -> Void
    @Environment(\.modelContext) private var db
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var notes = ""
    @State private var name = ""
    @State private var preferences = ""
    @State private var phone = ""
    @State private var message = ""
    @State private var editing = false
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

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
                            message = ""
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
                            VStack(spacing: 14) {
                                HStack(spacing: 14) {
                                    SalonClientInitials(name: client.name, large: true)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(client.name).font(.title2.bold())
                                        Label(client.phone.isEmpty ? "Téléphone non renseigné" : client.phone,
                                              systemImage: "phone")
                                            .font(.subheadline)
                                    }
                                    Spacer(minLength: 0)
                                }
                                let stats = textSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                    : AnyLayout(HStackLayout(spacing: 12))
                                stats {
                                    stat("Visites", value: "\(Set(history.map(\.order)).count)", symbol: "calendar")
                                    stat("Total des prestations", value: serviceTotal, symbol: "creditcard")
                                }
                            }
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "list.clipboard")
                                .font(.title3)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Préférences et notes techniques")
                                    .font(.subheadline.bold())
                                    .accessibilityAddTraits(.isHeader)
                                if client.preferences.isEmpty && client.notes.isEmpty {
                                    Text("Aucune préférence ni note renseignée.").font(.caption)
                                }
                                if !client.preferences.isEmpty { Text(client.preferences).font(.caption) }
                                if !client.notes.isEmpty { Text(client.notes).font(.caption) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(COVITheme.Metrics.cardPadding)
                        .background(COVITheme.champagne,
                                    in: RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius))
                        VStack(alignment: .leading, spacing: 10) {
                            COVISectionTitle("Historique des prestations")
                            COVICard {
                                VStack(alignment: .leading, spacing: 6) {
                                    if history.isEmpty {
                                        Text("Aucune prestation encaissée.")
                                            .foregroundStyle(COVITheme.secondaryText)
                                    }
                                    ForEach(history.prefix(3)) { row in
                                        if row.id != history.first?.id { Divider() }
                                        COVIIconRow(symbol: "calendar", title: row.title,
                                            detail: "\(row.date.formatted(date: .abbreviated, time: .omitted)) · \(row.stylist) · \(COVIMoney.text(row.gross, currency: currency))",
                                            accessory: nil)
                                    }
                                }
                            }
                        }
                    }
                    .foregroundStyle(COVITheme.navy)
                    .padding(18)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !editing && !textSize.isAccessibilitySize {
                COVIButton("Nouveau rendez-vous", systemImage: "plus", action: onNewBooking)
                    .accessibilityHint("Pour \(client.name)")
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(COVITheme.cream)
            }
        }
        .background(COVIBackdrop())
        .navigationTitle(editing ? "Modifier la fiche" : "Fiche client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !editing && textSize.isAccessibilitySize {
                Button("Nouveau rendez-vous", systemImage: "plus", action: onNewBooking)
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Pour \(client.name)")
            }
            Button(editing ? "Annuler" : "Modifier") {
                if !editing {
                    name = client.name
                    notes = client.notes
                    preferences = client.preferences
                    phone = client.phone
                    message = ""
                }
                editing.toggle()
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.salonProfileID == client.id {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var serviceTotal: String {
        let total = history.reduce(Decimal.zero) { $0 + Decimal($1.gross) }
        return "\(total.formatted(.number.grouping(.automatic))) \(currency == "XAF" ? "FCFA" : currency)"
    }

    private func stat(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: textSize.isAccessibilitySize ? .leading : .center, spacing: 4) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(COVITheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: textSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
    }
}
