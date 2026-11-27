import SwiftUI
import SwiftData

struct RestaurantSpace: View {
    let shop: Establishment
    let tab: BusinessTab
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    @Environment(\.modelContext) private var db
    @Query private var tables: [DiningTable]
    @Query private var orders: [CommerceOrder]
    @Query private var payments: [PaymentRecord]
    @Query private var menu: [CatalogItem]
    @Query(sort: \OrderLine.sentAt) private var lines: [OrderLine]
    @State private var showFloorPlan = true
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var filter = "Toutes"
    @State private var setup = false
    @State private var message = ""
    init(shop: Establishment, tab: BusinessTab, actor: UUID, role: StaffRole, pin: PINManager) {
        self.shop = shop; self.tab = tab; self.actor = actor; self.role = role; self.pin = pin
        let id = shop.id
        _tables = Query(filter: #Predicate<DiningTable> { $0.establishmentID == id }, sort: \.label)
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id })
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.establishmentID == id })
        _menu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
    }
    var service: RestaurantService { RestaurantService(shop: shop, actor: actor, role: role, pin: pin, db: db) }
    func state(_ table: DiningTable) -> String {
        if table.isOccupied && orders.contains(where: { $0.id == table.activeSessionID && $0.state == .completed }) {
            return RestaurantFloorState.paidOccupied.rawValue
        }
        return table.billRequested ? "Addition demandée" : table.isOccupied ? "Occupée" : "Libre"
    }
    var filteredTables: [DiningTable] {
        tables.filter { table in
            filter == "Toutes" || (filter == "Occupées" && table.isOccupied) ||
                (filter == "Libres" && !table.isOccupied)
        }
    }
    var body: some View {
        Group {
            if tab == .tables && showFloorPlan {
                RestaurantFloorPlan(tables: tables, orders: orders, lines: lines,
                    payments: payments, service: service) { table in
                    tableDetail(table)
                }
            } else {
                gridOrKitchen
            }
        }
        .background(COVIBackdrop())
        .navigationTitle(tab == .kitchen ? "Cuisine" : tab == .tables && showFloorPlan ? "Salle" : tab.title)
        .toolbar {
            if tab == .tables {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFloorPlan.toggle() } label: {
                        Label(showFloorPlan ? "Afficher la liste" : "Afficher le plan",
                              systemImage: showFloorPlan ? "list.bullet" : "square.grid.3x3")
                    }
                    if service.admin { Button("Configurer") { setup = true } }
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .onAppear {
            if diagnostics?.scenario == .restaurantTables { showFloorPlan = false }
        }
#endif
        .sheet(isPresented: $setup) { RestaurantSetup(service: service, tables: tables) }
        .alert("Restaurant", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("OK") {}
        } message: { Text(message) }
    }

    private func tableDetail(_ table: DiningTable) -> some View {
        RestaurantTable(table: table, order: orders.first { $0.id == table.activeSessionID }, menu: menu,
                        lines: lines.filter { $0.orderID == table.activeSessionID }, service: service)
    }

    private var gridOrKitchen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if tab == .kitchen {
                    RestaurantKitchenBoard(tables: tables, orders: orders, lines: lines) { ticketLines, phase, table, order in
                        perform { try service.advance(ticketLines, from: phase, table: table, order: order) }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(["Toutes", "Occupées", "Libres"], id: \.self) { option in
                            Button { filter = option } label: {
                                let count = option == "Toutes" ? tables.count : option == "Occupées" ? tables.filter(\.isOccupied).count : tables.filter { !$0.isOccupied }.count
                                Text("\(option) (\(count))")
                                    .font(.subheadline.weight(.semibold))
                                    .minimumScaleFactor(0.75).lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(filter == option ? .white : COVITheme.navy)
                                    .background(filter == option ? COVITheme.navy : .white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(filter == option ? .isSelected : [])
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        ForEach(filteredTables) { t in
                            NavigationLink {
                                tableDetail(t)
                            } label: {
                                COVICard {
                                    VStack(spacing: 12) {
                                        Image(systemName: "table.furniture")
                                            .font(.system(size: 36))
                                            .foregroundStyle(t.billRequested ? COVITheme.warning : t.isOccupied ? COVITheme.navy : COVITheme.success)
                                            .frame(height: 48)
                                        ViewThatFits(in: .horizontal) {
                                            HStack(spacing: 5) {
                                                Text(t.label).font(.headline)
                                                Text("(\(t.capacity) pers.)").font(.caption)
                                            }
                                            VStack(spacing: 3) {
                                                Text(t.label).font(.headline)
                                                Text("(\(t.capacity) pers.)").font(.caption)
                                            }
                                        }
                                        .multilineTextAlignment(.center)
                                        COVIBadge(title: state(t),
                                            tint: t.billRequested ? COVITheme.warningTint : t.isOccupied ? COVITheme.champagne : COVITheme.successTint,
                                            foreground: t.billRequested ? COVITheme.warning : t.isOccupied ? COVITheme.navy : COVITheme.success)
                                        if let order = orders.first(where: { $0.id == t.activeSessionID }) {
                                            VStack(spacing: 3) {
                                                Text(order.state == .completed ? "Addition réglée" : t.billRequested ? "Reste dû" : "En cours")
                                                    .font(.caption)
                                                Text((order.state == .completed ? order.totalMinor : RestaurantBill.remaining(order, payments: payments)).map {
                                                    COVIMoney.text($0, currency: shop.currencyCode)
                                                } ?? "À vérifier")
                                                    .font(.subheadline.bold())
                                            }
                                            .multilineTextAlignment(.center)
                                        } else if !t.isOccupied {
                                            Text("Prête au service").font(.caption)
                                        }
                                    }
                                    .foregroundStyle(COVITheme.navy)
                                    .frame(maxWidth: .infinity, minHeight: 174)
                                }
                                .overlay(RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius)
                                    .stroke(t.isOccupied ? COVITheme.navy : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if tables.isEmpty { Text("Aucune table configurée.") }
                }
            }.padding(18)
        }
    }
    func perform(_ work: () throws -> Void) {
        do { try work(); HapticService.confirm() } catch { message = error.localizedDescription; HapticService.error() }
    }
}

struct RestaurantTable: View {
    let table: DiningTable
    let order: CommerceOrder?
    let menu: [CatalogItem]
    let lines: [OrderLine]
    let service: RestaurantService
    @State private var ordering = false
    @State private var closing = false
    @State private var editingGuests = false
    @State private var confirmingDeparture = false
    @State private var incidentLine: OrderLine?
    @Query private var payments: [PaymentRecord]
    @Query private var incidents: [RestaurantIncident]
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var message = ""

    init(table: DiningTable, order: CommerceOrder?, menu: [CatalogItem], lines: [OrderLine],
         service: RestaurantService) {
        self.table = table
        self.order = order
        self.menu = menu
        self.lines = lines
        self.service = service
        let orderID = order?.id ?? UUID()
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.orderID == orderID })
        let shopID = service.shop.id
        _incidents = Query(filter: #Predicate<RestaurantIncident> {
            $0.establishmentID == shopID && $0.orderID == orderID
        })
    }

    var body: some View {
        let currentOrder = table.activeSessionID == order?.id ? order : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let order = currentOrder, order.state == .completed {
                    paidTable(order)
                } else if let order = currentOrder {
                    COVICard {
                        VStack(alignment: .leading, spacing: 10) {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    openingTime(order)
                                    Spacer()
                                    Text("\(table.capacity) places")
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    openingTime(order)
                                    Text("\(table.capacity) places")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let counts = order.restaurantGuestCount {
                                Label("\(counts) convives", systemImage: "person.2")
                            } else {
                                Label("Convives non renseignés", systemImage: "person.2")
                            }
                            if !table.billRequested && (service.admin || service.role == .waiter) {
                                Button("Confirmer les convives") { editingGuests = true }
                                    .fontWeight(.semibold)
                                    .frame(minHeight: 44)
                            }
                        }
                        .font(.subheadline)
                    }
                    COVISectionTitle("Détail de la session")
                    COVICard {
                        VStack(spacing: 13) {
                            if lines.isEmpty {
                                Text("Aucun plat commandé pour cette table.")
                                    .foregroundStyle(COVITheme.secondaryText)
                            }
                            ForEach(lines) { line in
                                if line.id != lines.first?.id { Divider() }
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "fork.knife")
                                        .font(.title3).foregroundStyle(COVITheme.navy)
                                        .frame(width: 52, height: 55)
                                        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("\(line.quantity) × \(line.dishName ?? "Article")").font(.headline)
                                        let (amount, overflow) = line.unitPriceMinor.multipliedReportingOverflow(by: Int64(line.quantity))
                                        if overflow || line.quantity <= 0 || line.unitPriceMinor < 0 {
                                            Text("Montant invalide").font(.subheadline).foregroundStyle(.red)
                                        } else {
                                            Text(COVIMoney.text(amount, currency: service.shop.currencyCode))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        if line.preparation == Prep.ready.rawValue {
                                            Button("Marquer servi") {
                                                run { try service.advance(line, from: .ready, table: table, order: order) }
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(COVITheme.blue)
                                        } else {
                                            let status = Prep(rawValue: line.preparation ?? "")
                                            COVIBadge(title: status?.rawValue ?? "Commandé",
                                                tint: status == .served ? COVITheme.successTint : COVITheme.blue.opacity(0.1),
                                                foreground: status == .served ? COVITheme.success : COVITheme.blue)
                                            if status == .served && service.admin {
                                                incidentAction(for: line)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "circle.stack").font(.title2)
                        Spacer()
                        Text("Reste à encaisser :").font(.headline)
                        Text(RestaurantBill.remaining(order, payments: payments).map {
                            COVIMoney.text($0, currency: service.shop.currencyCode)
                        } ?? "À vérifier")
                            .font(.headline)
                    }
                    .foregroundStyle(COVITheme.navy)
                    .padding(16)
                    .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 15))
                    if table.billRequested {
                        COVIButton("Encaisser") { closing = true }
                    } else {
                        HStack(spacing: 12) {
                            COVIButton("Ajouter", systemImage: "plus", role: .secondary) { ordering = true }
                            COVIButton("Demander l’addition") {
                                run { try service.finish(table, order: order, paid: false) }
                            }
                        }
                    }
                } else if !table.isOccupied {
                    COVICard {
                        VStack(alignment: .leading, spacing: 12) {
                            COVIBadge(title: "Libre", tint: COVITheme.successTint, foreground: COVITheme.success)
                            Text("Ouvrez une session pour prendre les commandes de cette table.")
                        }
                    }
                    COVIButton("Ouvrir une session") { editingGuests = true }
                } else {
                    Text("Session à réconcilier.").foregroundStyle(.red)
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(18)
        }
        .background(COVIBackdrop())
        .navigationTitle(table.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $incidentLine) { line in
            if let order {
                RestaurantIncidentEditor(line: line, table: table, order: order, service: service)
            }
        }
        .confirmationDialog("Confirmer le départ des convives", isPresented: $confirmingDeparture,
                            titleVisibility: .visible) {
            Button("Libérer la table") {
                if let order = currentOrder { run { try service.release(table, after: order) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette table redeviendra disponible.")
        }
        .sheet(isPresented: $closing) {
            if let order {
                RestaurantCheckout(table: table, order: order, service: service)
                    .presentationDetents([.fraction(0.84), .large])
                    .presentationDragIndicator(.visible)
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if diagnostics?.scenario == .restaurantPayment { closing = true }
            if diagnostics?.scenario == .restaurantIncident {
                incidentLine = lines.first { $0.preparation == Prep.served.rawValue }
            }
        }
#endif
        .sheet(isPresented: $editingGuests) {
            RestaurantGuestEditor(table: table, existingCount: order?.restaurantGuestCount) { count in
                if let order { try service.confirmGuests(count, at: table, order: order) }
                else { try service.open(table, guestCount: count) }
            }
        }
        .sheet(isPresented: $ordering) { if let order { RestaurantComposer(menu: menu, table: table, order: order, service: service) } }
    }
    private func incidentAction(for line: OrderLine) -> some View {
        Group {
            if incidents.contains(where: { $0.lineID == line.id }) {
                Label("Incident consigné", systemImage: "checkmark.circle")
                    .foregroundStyle(COVITheme.secondaryText)
            } else {
                Button("Déclarer un incident") { incidentLine = line }
                    .foregroundStyle(COVITheme.blue)
                    .frame(minHeight: 44)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
    private func paidTable(_ order: CommerceOrder) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            COVICard {
                VStack(alignment: .leading, spacing: 10) {
                    COVIBadge(title: RestaurantFloorState.paidOccupied.rawValue,
                              tint: RestaurantFloorState.paidOccupied.tint)
                    LabeledContent("Addition réglée",
                                   value: COVIMoney.text(order.totalMinor, currency: service.shop.currencyCode))
                        .font(.headline)
                    if let guests = order.restaurantGuestCount {
                        Label("\(guests) convives", systemImage: "person.2")
                    }
                    Text("Confirmez le départ pour rendre la table disponible.")
                        .font(.subheadline)
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }
            if service.admin || service.role == .waiter {
                COVIButton("Confirmer le départ", systemImage: "checkmark") { confirmingDeparture = true }
            }
        }
    }

    private func openingTime(_ order: CommerceOrder) -> some View {
        Label("Ouverte à \(order.createdAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
    }

    func run(_ work: () throws -> Void) {
        do { try work(); message = ""; HapticService.confirm() } catch { message = error.localizedDescription; HapticService.error() }
    }
}

private struct RestaurantGuestEditor: View {
    let table: DiningTable
    let save: (Int) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var count: Int
    @State private var message = ""

    init(table: DiningTable, existingCount: Int?, save: @escaping (Int) throws -> Void) {
        self.table = table
        self.save = save
        _count = State(initialValue: min(max(1, table.capacity), max(1, existingCount ?? 1)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Capacité de la table", value: "\(table.capacity) places")
                    Stepper("Convives présents : \(count)", value: $count, in: 1...max(1, min(table.capacity, 100)))
                } footer: {
                    Text("Indiquez le nombre de personnes réellement présentes.")
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(COVITheme.cream)
            .navigationTitle(table.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmer") {
                        do {
                            try save(count)
                            HapticService.confirm()
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                            HapticService.error()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
