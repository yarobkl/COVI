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
    @Query private var menu: [CatalogItem]
    @Query(sort: \OrderLine.sentAt) private var lines: [OrderLine]
    @State private var filter = "Toutes"
    @State private var phase = Prep.cooking
    @State private var setup = false
    @State private var message = ""
    init(shop: Establishment, tab: BusinessTab, actor: UUID, role: StaffRole, pin: PINManager) {
        self.shop = shop; self.tab = tab; self.actor = actor; self.role = role; self.pin = pin
        let id = shop.id
        _tables = Query(filter: #Predicate<DiningTable> { $0.establishmentID == id }, sort: \.label)
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id })
        _menu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
    }
    var service: RestaurantService { RestaurantService(shop: shop, actor: actor, role: role, pin: pin, db: db) }
    func state(_ t: DiningTable) -> String { t.billRequested ? "Addition demandée" : t.isOccupied ? "Occupée" : "Libre" }
    var filteredTables: [DiningTable] {
        tables.filter { table in
            filter == "Toutes" || (filter == "Occupées" && table.isOccupied) ||
                (filter == "Libres" && !table.isOccupied)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if tab == .kitchen {
                    HStack(spacing: 8) {
                        ForEach(Prep.allCases, id: \.self) { option in
                            Button { phase = option } label: {
                                Text(option == .cooking ? "À préparer" : option == .ready ? "Prêts" : "Servis")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(phase == option ? .white : COVITheme.navy)
                                    .background(phase == option ? COVITheme.navy : .white, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    let activeOrders = Set(tables.compactMap(\.activeSessionID))
                    if !lines.contains(where: { activeOrders.contains($0.orderID) && $0.preparation == phase.rawValue }) {
                        ContentUnavailableView("Aucune commande", systemImage: "checkmark.circle",
                            description: Text("Les nouveaux plats envoyés en cuisine apparaîtront ici."))
                    }
                    ForEach(tables) { t in
                        if let order = orders.first(where: { $0.id == t.activeSessionID }) {
                            ForEach(lines.filter { $0.orderID == order.id && $0.preparation == phase.rawValue }) { line in
                                COVICard { VStack(alignment: .leading, spacing: 15) {
                                    HStack {
                                        Label(t.label, systemImage: "fork.knife")
                                            .font(.headline)
                                        Spacer()
                                        if let sent = line.sentAt { COVIBadge(title: sent.formatted(date: .omitted, time: .shortened), tint: COVITheme.warningTint, foreground: COVITheme.warning) }
                                    }
                                    Text("\(line.quantity) × \(line.dishName ?? "Article")")
                                        .font(.title3.bold())
                                    if phase == .cooking || phase == .ready {
                                        COVIButton(phase == .cooking ? "Marquer prêt" : "Marquer servi") {
                                            perform { try service.advance(line, from: phase, table: t, order: order) }
                                        }
                                    }
                                }.foregroundStyle(COVITheme.navy) }
                            }
                        }
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
                                RestaurantTable(table: t, order: orders.first { $0.id == t.activeSessionID }, menu: menu,
                                                lines: lines.filter { $0.orderID == t.activeSessionID }, service: service)
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
                                                Text(t.billRequested ? "Reste dû" : "En cours")
                                                    .font(.caption)
                                                Text(COVIMoney.text(order.totalMinor, currency: shop.currencyCode))
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
        }.background(COVIBackdrop()).navigationTitle(tab == .kitchen ? "Cuisine" : tab.title)
        .toolbar { if service.admin && tab == .tables { Button("Configurer") { setup = true } } }
        .sheet(isPresented: $setup) { RestaurantSetup(service: service, menu: menu, tables: tables) }
        .alert("Restaurant", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("OK") {} } message: { Text(message) }
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
    @State private var tender = Tender.cash
    @State private var received = ""
    @State private var confirmed = false
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let order {
                    COVICard {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Label("Ouverte à \(order.createdAt.formatted(date: .omitted, time: .shortened))",
                                    systemImage: "clock")
                                Spacer()
                                Text("\(table.capacity) places")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Ouverte à \(order.createdAt.formatted(date: .omitted, time: .shortened))",
                                    systemImage: "clock")
                                Text("\(table.capacity) places")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(COVIMoney.text(order.totalMinor, currency: service.shop.currencyCode))
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
                    COVIButton("Ouvrir une session") { run { try service.open(table) } }
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
        .sheet(isPresented: $closing) {
            if let order {
                NavigationStack {
                    Form {
                        Section("Paiement confirmé en caisse") {
                            LabeledContent("Addition", value: "\(order.totalMinor) \(service.shop.currencyCode)")
                            Picker("Moyen de paiement", selection: $tender) {
                                ForEach(Tender.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            if tender == .cash {
                                TextField("Montant reçu en " + service.shop.currencyCode, text: $received)
                                    .keyboardType(.numberPad)
                                if let amount = Int64(received), amount >= order.totalMinor {
                                    LabeledContent("Monnaie à rendre", value: "\(amount - order.totalMinor) \(service.shop.currencyCode)")
                                }
                            } else {
                                Toggle("J’ai vérifié la réception de ce paiement", isOn: $confirmed)
                            }
                        }
                        Section {
                            Button("Confirmer et libérer la table") {
                                run { try service.finish(table, order: order, paid: true, tender: tender,
                                                         received: Int64(received), confirmed: confirmed) }
                                if message.isEmpty { closing = false; received = ""; confirmed = false }
                            }
                            .disabled(tender == .cash ? (Int64(received) ?? -1) < order.totalMinor : !confirmed)
                        }
                        if !message.isEmpty { Text(message).foregroundStyle(.red) }
                    }
                    .navigationTitle("Règlement de la table")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { closing = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $ordering) { if let order { RestaurantComposer(menu: menu, table: table, order: order, service: service) } }
    }
    func run(_ work: () throws -> Void) {
        do { try work(); message = ""; HapticService.confirm() } catch { message = error.localizedDescription; HapticService.error() }
    }
}
