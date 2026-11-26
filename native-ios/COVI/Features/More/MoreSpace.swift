import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

enum COVICSV {
    enum Cell {
        case text(String)
        case number(String)
        static func money(_ amount: Decimal) -> Cell {
            .number(NSDecimalNumber(decimal: amount).stringValue)
        }
    }

    static func encode(headers: [String], rows: [[Cell]]) -> String {
        func escaped(_ cell: Cell) -> String {
            let value: String
            switch cell {
            case .text(let content):
                // A CSV quote alone does not prevent spreadsheet formula execution.
                let first = content.drop(while: { $0.isWhitespace }).first
                let sanitized = first.map { "=+-@".contains($0) } == true ? "'" + content : content
                value = sanitized
            case .number(let numeric):
                value = numeric
            }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let titleRow = headers.map { escaped(.text($0)) }.joined(separator: ",")
        let content = rows.filter { $0.count == headers.count }.map {
            $0.map(escaped).joined(separator: ",")
        }
        return ([titleRow] + content).joined(separator: "\r\n") + "\r\n"
    }
}

struct COVICSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var content: String

    init(_ content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents,
              let string = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

@Model final class MaintenanceEntry {
    var actor: UUID
    var shop: UUID
    var action: String
    var date: Date
    init(_ action: String, actor: UUID, shop: UUID) {
        self.action = action
        self.actor = actor
        self.shop = shop
        date = .now
    }
}

struct MoreSpace: View {
    let shop: Establishment
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    let onSwitchShop: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var db
    @Query private var ownedShops: [Establishment]
    @Query private var salonMenu: [CatalogItem]
    @Query private var salonSales: [SalonSaleLine]
    @Query private var salonVisits: [SalonVisit]
    @Query private var restaurantTables: [DiningTable]
    @Query private var restaurantOrders: [CommerceOrder]
    @Query private var restaurantPayments: [PaymentRecord]
    @Query private var restaurantRefunds: [Refund]
    private enum Destination: Hashable { case settings, salonReport, restaurantReport, restaurantTeam, restaurantMenu, restaurantDrinks }
    @State private var destination: Destination?
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    private var managesSalon: Bool { shop.kind == .salon && (role == .owner || role == .manager) }
    private var managesRestaurant: Bool { shop.kind == .restaurant && (role == .owner || role == .manager) }

    init(shop: Establishment, actor: UUID, role: StaffRole, pin: PINManager,
         onSwitchShop: @escaping () -> Void) {
        self.shop = shop; self.actor = actor; self.role = role; self.pin = pin
        self.onSwitchShop = onSwitchShop
        let id = shop.id
        _ownedShops = Query(filter: #Predicate<Establishment> { $0.ownerID == actor && !$0.archived })
        _salonMenu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
        _salonSales = Query(filter: #Predicate<SalonSaleLine> { $0.shop == id }, sort: \.date, order: .reverse)
        _salonVisits = Query(filter: #Predicate<SalonVisit> { $0.shop == id }, sort: \.start, order: .reverse)
        _restaurantTables = Query(filter: #Predicate<DiningTable> { $0.establishmentID == id }, sort: \.label)
        _restaurantOrders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id }, sort: \.createdAt, order: .reverse)
        _restaurantPayments = Query(filter: #Predicate<PaymentRecord> { $0.establishmentID == id })
        _restaurantRefunds = Query(filter: #Predicate<Refund> { $0.establishmentID == id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileCard

                if managesSalon {
                    COVISectionTitle("Gestion du salon")
                    COVICard {
                        VStack(spacing: 4) {
                            NavigationLink {
                                SalonCatalog(shop: shop, menu: salonMenu, actor: actor)
                            } label: {
                                COVIIconRow(symbol: "scissors", title: "Catalogue prestations & produits", detail: nil)
                            }
                            Divider()
                            Button { destination = .salonReport } label: {
                                COVIIconRow(symbol: "chart.bar", title: "Rapports & Commissions équipe", detail: nil)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { LocalShopCard(shop: shop) } label: {
                                COVIIconRow(symbol: "link", title: "Fiche à partager et QR", detail: "Fiche locale")
                            }
                            Divider()
                            NavigationLink { SalonTeamSettings(shop: shop, actor: actor) } label: {
                                COVIIconRow(symbol: "person.3", title: "Équipe, Rôles & Codes PIN", detail: nil)
                            }
                        }
                    }
                }

                if managesRestaurant {
                    COVISectionTitle("Gestion du restaurant")
                    COVICard {
                        VStack(spacing: 4) {
                            Button { destination = .restaurantMenu } label: {
                                COVIIconRow(symbol: "fork.knife", title: "Gestion de la carte", detail: nil)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            Button { destination = .restaurantDrinks } label: {
                                COVIIconRow(symbol: "wineglass", title: "Stock boissons", detail: nil)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink {
                                RestaurantSetup(service: RestaurantService(shop: shop, actor: actor,
                                    role: role, pin: pin, db: db), tables: restaurantTables)
                            } label: {
                                COVIIconRow(symbol: "table.furniture", title: "Configuration des tables", detail: nil)
                            }
                            Divider()
                            Button { destination = .restaurantReport } label: {
                                COVIIconRow(symbol: "chart.bar", title: "Rapports service", detail: nil)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            Button { destination = .restaurantTeam } label: {
                                COVIIconRow(symbol: "person.3", title: "Équipe & Accès", detail: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                COVISectionTitle("Système & Multi-espaces")
                COVICard {
                    VStack(spacing: 4) {
                        Button(action: onSwitchShop) {
                            COVIIconRow(symbol: "storefront", title: "Changer d’établissement",
                                detail: shop.name)
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { COVISyncCentre(shop: shop) } label: {
                            COVIIconRow(symbol: "icloud", title: "Centre de synchronisation hors-ligne", detail: nil)
                        }
                        Divider()
                        Button { destination = .settings } label: {
                            COVIIconRow(symbol: "gearshape", title: "Profil et paramètres de sécurité", detail: nil)
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { HelpPrivacyView(kind: shop.kind) } label: {
                            COVIIconRow(symbol: "questionmark.circle", title: "Aide & Confidentialité", detail: nil)
                        }
                    }
                }

                COVISectionTitle("Gestion du commerce")
                COVICard {
                    VStack(spacing: 4) {
                        NavigationLink { CommerceReceiptHistory(shop: shop) } label: {
                            COVIIconRow(symbol: "receipt", title: "Historique des reçus", detail: nil)
                        }
                        if role == .owner || role == .manager {
                            Divider()
                            NavigationLink {
                                ExpenseSpace(shop: shop, actor: actor, canCancel: role == .owner)
                            } label: {
                                COVIIconRow(symbol: "wallet.pass", title: "Dépenses du commerce", detail: nil)
                            }
                            Divider()
                            NavigationLink { FinanceOverview(shop: shop) } label: {
                                COVIIconRow(symbol: "chart.bar.xaxis", title: "Bilan de trésorerie", detail: nil)
                            }
                        }
                        if role == .owner {
                            Divider()
                            NavigationLink { OwnerSettings(shop: shop, pinManager: pin) } label: {
                                COVIIconRow(symbol: "lock.shield", title: "Équipe & Accès sécurisés", detail: nil)
                            }
                        }
                    }
                }

            }
            .foregroundStyle(COVITheme.navy)
            .multilineTextAlignment(.leading)
            .padding(18)
        }
        .navigationTitle("Plus")
        .background(COVIBackdrop())
        .navigationDestination(item: $destination) { screen in
            switch screen {
            case .settings:
                SystemSettings(shop: shop, actor: actor, pin: pin)
            case .salonReport:
                if managesSalon {
                    SalonReport(sales: salonSales, visits: salonVisits, currency: shop.currencyCode)
                }
            case .restaurantReport:
                if managesRestaurant {
                    RestaurantFinanceReport(shop: shop, orders: restaurantOrders,
                        payments: restaurantPayments, refunds: restaurantRefunds)
                }
            case .restaurantTeam:
                if managesRestaurant {
                    RestaurantTeamAccess(shop: shop, actor: actor, pin: pin)
                }
            case .restaurantDrinks:
                if managesRestaurant {
                    RestaurantDrinkStock(service: RestaurantService(shop: shop, actor: actor,
                        role: role, pin: pin, db: db))
                }
            case .restaurantMenu:
                if managesRestaurant {
                    RestaurantMenuManagement(service: RestaurantService(shop: shop, actor: actor,
                        role: role, pin: pin, db: db))
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if managesSalon, diagnostics?.scenario == .salonReport { destination = .salonReport }
            if managesRestaurant, diagnostics?.scenario == .restaurantReport { destination = .restaurantReport }
            if managesRestaurant, diagnostics?.scenario == .restaurantTeam { destination = .restaurantTeam }
            if managesRestaurant, diagnostics?.scenario == .restaurantMenu { destination = .restaurantMenu }
            if managesRestaurant, diagnostics?.scenario == .restaurantDrinks { destination = .restaurantDrinks }
            if shop.kind == .salon, diagnostics?.scenario == .salonSettings { destination = .settings }
        }
#endif
    }

    private var profileCard: some View {
        Button { destination = .settings } label: {
            COVICard {
                HStack(spacing: 12) {
                    Text(initials.isEmpty ? "C" : initials)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 54, height: 54)
                        .background(COVITheme.champagne, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.displayName.isEmpty ? "Mon profil COVI" : session.displayName)
                            .font(.headline)
                        Text(profileSubtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(COVITheme.navy, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre les paramètres")
    }

    private var profileSubtitle: String {
        guard role == .owner else { return roleName }
        return "\(roleName) · \(ownedShops.count)/\(EstablishmentPolicy.maximumActivePerOwner) espaces"
    }

    private var initials: String {
        let parts = session.displayName.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }

    private var roleName: String {
        switch role {
        case .owner: "Propriétaire"
        case .manager: "Responsable"
        case .cashier: "Caissier"
        case .waiter: "Serveur"
        case .kitchen: "Cuisine"
        case .stylist: "Coiffeur / Coiffeuse"
        }
    }
}

private struct COVISyncCentre: View {
    let shop: Establishment
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Query private var outbox: [OutboxEvent]
    @State private var syncing = false
    @State private var result = ""

    init(shop: Establishment) {
        self.shop = shop
        let id = shop.id
        _outbox = Query(filter: #Predicate<OutboxEvent> { $0.establishmentID == id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                COVISectionTitle("Synchronisation")
                COVICard {
                    HStack(spacing: 15) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.largeTitle).foregroundStyle(COVITheme.warning)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(session.usesAppleAccount ? "Sauvegarde iCloud" : "Mode hors-ligne actif")
                                .font(.headline)
                            Text("\(outbox.filter { $0.state == .pending }.count) opérations en attente · Cache local conservé")
                                .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                        }
                    }
                }
                COVIButton("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await syncNow() }
                }
                .disabled(syncing || !session.usesAppleAccount)
                if syncing { ProgressView("Synchronisation en cours…") }
                if !result.isEmpty { Text(result).foregroundStyle(COVITheme.navy) }
                COVISectionTitle("Journal des opérations")
                COVICard {
                    if outbox.isEmpty { Text("Aucune opération en attente.") }
                    ForEach(outbox.sorted { $0.createdAt > $1.createdAt }.prefix(30)) { event in
                        HStack(spacing: 13) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.eventType).font(.subheadline.weight(.semibold))
                                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(COVITheme.secondaryText)
                            }
                            Spacer()
                            COVIBadge(title: status(event.state),
                                tint: event.state == .synced ? COVITheme.successTint : COVITheme.warningTint)
                        }
                        Divider()
                    }
                }
                Text("COVI n’exécute aucun débit bancaire. Les paiements Mobile Money sont confirmés manuellement.")
                    .font(.footnote).foregroundStyle(COVITheme.secondaryText)
            }
            .padding(18)
        }
        .background(COVIBackdrop())
        .navigationTitle("Synchronisation")
    }

    private func status(_ value: SyncState) -> String {
        switch value {
        case .pending: "En attente"
        case .syncing: "En cours"
        case .synced: "Confirmée"
        case .conflict: "À vérifier"
        case .failed: "Échec"
        }
    }

    private func syncNow() async {
        guard session.usesAppleAccount, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await CloudShopDirectory.reconcile(owner: shop.ownerID, context: context)
            try await SyncCoordinator.cycle(shop: shop, context: context)
            try await CloudReceiptArchive.cycle(shop: shop, context: context)
            try await CloudExpenseLedger.cycle(shop: shop, context: context)
            try await CloudOperationalSync.cycle(shop: shop, context: context)
            result = "Synchronisation terminée."
            HapticService.confirm()
        } catch {
            result = "Synchronisation suspendue : \(error.localizedDescription). Vos données restent sur cet appareil."
            HapticService.error()
        }
    }
}

struct RestaurantCashReportSnapshot {
    let receipts: [PaymentRecord]
    let refunded: Decimal
    let refundCount: Int
    let gross: Decimal
    let cash: Decimal
    let mobile: Decimal
    let tableCount: Int
    let averageTicket: Decimal
    var other: Decimal { gross - cash - mobile }
    var net: Decimal { gross - refunded }

    init(shop: UUID, month: Date, orders: [CommerceOrder], payments: [PaymentRecord],
         refunds: [Refund], calendar: Calendar = .current) {
        let periodReceipts = payments.filter {
            $0.establishmentID == shop && $0.amountMinor > 0 &&
            calendar.isDate($0.confirmedAt, equalTo: month, toGranularity: .month)
        }
        receipts = periodReceipts
        let periodRefunds = refunds.filter {
            $0.establishmentID == shop && $0.amountMinor > 0 &&
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
        refundCount = periodRefunds.count
        refunded = periodRefunds.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }
        gross = periodReceipts.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }
        cash = periodReceipts.filter { $0.method == Tender.cash.rawValue }
            .reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }
        mobile = periodReceipts.filter { Tender(rawValue: $0.method)?.isMobileMoney == true }
            .reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }

        let paidHere = payments.filter { $0.establishmentID == shop && $0.amountMinor > 0 }
        let lastPaymentDates = Dictionary(grouping: paidHere, by: \.orderID)
            .compactMapValues { $0.map(\.confirmedAt).max() }
        let tableOrders = orders.filter {
            guard $0.establishmentID == shop, $0.tableID != nil, $0.state == .completed,
                  let settledAt = lastPaymentDates[$0.id] else { return false }
            return calendar.isDate(settledAt, equalTo: month, toGranularity: .month)
        }
        tableCount = tableOrders.count
        let tableTotal = tableOrders.reduce(Decimal.zero) { $0 + Decimal($1.totalMinor) }
        averageTicket = tableOrders.isEmpty ? .zero : tableTotal / Decimal(tableOrders.count)
    }
}

private struct RestaurantFinanceReport: View {
    let shop: Establishment
    let orders: [CommerceOrder]
    let payments: [PaymentRecord]
    let refunds: [Refund]
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var month = Date.now
    @State private var choosingMonth = false
    @State private var exporting = false
    @State private var exportError = ""

    var body: some View {
        let snapshot = RestaurantCashReportSnapshot(shop: shop.id, month: month, orders: orders,
            payments: payments, refunds: refunds)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if textSize.isAccessibilitySize { monthButton }
                summaryCard(snapshot)
                COVISectionTitle("Répartition et activité")
                activityCard(snapshot)
                COVIButton("Exporter le journal de caisse", systemImage: "square.and.arrow.down", role: .secondary) {
                    exportError = ""
                    exporting = true
                }
                if !exportError.isEmpty { Text(exportError).foregroundStyle(.red) }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
        }
        .background(COVIBackdrop())
        .navigationTitle("Rapports service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !textSize.isAccessibilitySize {
                ToolbarItem(placement: .topBarTrailing) { monthButton }
            }
        }
        .sheet(isPresented: $choosingMonth) {
            NavigationStack {
                Form {
                    DatePicker("Date du mois à consulter", selection: $month, displayedComponents: .date)
                }
                .navigationTitle("Mois du rapport")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { choosingMonth = false }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .fileExporter(isPresented: $exporting,
            document: COVICSVDocument(COVICSV.encode(
                headers: ["Date", "Méthode", "Montant", "Devise"],
                rows: snapshot.receipts.map { payment in
                    [.text(payment.confirmedAt.formatted(.iso8601)), .text(payment.method),
                     .number(String(payment.amountMinor)), .text(shop.currencyCode)]
                })),
            contentType: .commaSeparatedText,
            defaultFilename: "COVI-journal-service") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .restaurantReport {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var monthButton: some View {
        let title = month.formatted(.dateTime.month(.abbreviated).year())
        return Button { choosingMonth = true } label: {
            HStack(spacing: 4) {
                Text(title)
                    .fixedSize(horizontal: !textSize.isAccessibilitySize, vertical: true)
                Image(systemName: "chevron.down").accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(COVITheme.champagne, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mois du rapport")
        .accessibilityValue(title)
    }

    private func summaryCard(_ snapshot: RestaurantCashReportSnapshot) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                Image(systemName: "chart.bar.fill")
                    .font(.title2).foregroundStyle(COVITheme.sand)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encaissements nets").font(.subheadline)
                    Text(money(snapshot.net)).font(.title.bold())
                }
            }
            Divider().overlay(.white.opacity(0.4)).accessibilityHidden(true)
            layout {
                summaryValue("Bruts", symbol: "banknote", amount: snapshot.gross)
                summaryValue("Remboursements", symbol: "arrow.uturn.backward", amount: -snapshot.refunded)
            }
        }
        .foregroundStyle(.white)
        .padding(COVITheme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius))
    }

    private func summaryValue(_ title: String, symbol: String, amount: Decimal) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(COVITheme.sand).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(money(amount)).font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func activityCard(_ snapshot: RestaurantCashReportSnapshot) -> some View {
        let tickets = snapshot.tableCount == 1 ? "1 ticket de table" : "\(snapshot.tableCount) tickets de table"
        return COVICard {
            VStack(alignment: .leading, spacing: 6) {
                tenderRow("Espèces encaissées", symbol: "banknote", amount: snapshot.cash,
                    gross: snapshot.gross, tint: COVITheme.successTint)
                Divider()
                tenderRow("Mobile Money", symbol: "iphone", amount: snapshot.mobile,
                    gross: snapshot.gross, tint: COVITheme.champagne)
                if snapshot.other > .zero {
                    Divider()
                    tenderRow("Autres moyens", symbol: "creditcard", amount: snapshot.other,
                        gross: snapshot.gross, tint: COVITheme.champagne)
                }
                Divider()
                COVIIconRow(symbol: "table.furniture", title: "Tables servies et ticket moyen",
                    detail: "\(tickets) · \(money(snapshot.averageTicket))",
                    accessory: nil)
                Divider()
                COVIIconRow(symbol: "arrow.uturn.backward", title: "Remboursements enregistrés",
                    detail: "\(snapshot.refundCount) · \(money(snapshot.refunded))", accessory: nil)
            }
        }
    }

    private func tenderRow(_ title: String, symbol: String, amount: Decimal, gross: Decimal, tint: Color) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 7))
        return layout {
            COVIIconRow(symbol: symbol, title: title, detail: money(amount), accessory: nil)
            if gross > .zero {
                Text((amount / gross).formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tint, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func money(_ amount: Decimal) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(0)))
        return "\(formatted) \(shop.currencyCode == "XAF" ? "FCFA" : shop.currencyCode)"
    }
}

struct FinanceSnapshot {
    let collected: Decimal
    let refunded: Decimal
    let expenses: Decimal
    let paymentCount: Int
    let byMethod: [(String, Decimal)]
    let byExpense: [(String, Decimal)]
    var balance: Decimal { collected - refunded - expenses }

    static func make(shop: UUID, month: Date, payments: [PaymentRecord],
                     refunds: [Refund], expenses: [ExpenseEntry],
                     calendar: Calendar = .current) -> FinanceSnapshot {
        let income = payments.filter {
            $0.establishmentID == shop && $0.amountMinor > 0 &&
            calendar.isDate($0.confirmedAt, equalTo: month, toGranularity: .month)
        }
        let returned = refunds.filter {
            $0.establishmentID == shop && $0.amountMinor > 0 &&
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
        let costs = expenses.filter {
            $0.establishmentID == shop && $0.voidedAt == nil && $0.amountMinor > 0 &&
            calendar.isDate($0.spentAt, equalTo: month, toGranularity: .month)
        }
        let methods = Dictionary(grouping: income, by: \.method).map { pair in
            (pair.key, pair.value.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) })
        }.sorted { $0.0 < $1.0 }
        let categories = Dictionary(grouping: costs, by: \.category).map { pair in
            (pair.key, pair.value.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) })
        }.sorted { $0.0 < $1.0 }
        return FinanceSnapshot(
            collected: income.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) },
            refunded: returned.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) },
            expenses: costs.reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) },
            paymentCount: income.count, byMethod: methods, byExpense: categories)
    }
}

struct FinanceOverview: View {
    let shop: Establishment
    @Query private var payments: [PaymentRecord]
    @Query private var refunds: [Refund]
    @Query private var expenses: [ExpenseEntry]
    @State private var month = Date()
    @State private var exporting = false
    @State private var exportError = ""

    init(shop: Establishment) {
        self.shop = shop
        let sid = shop.id
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.establishmentID == sid })
        _refunds = Query(filter: #Predicate<Refund> { $0.establishmentID == sid })
        _expenses = Query(filter: #Predicate<ExpenseEntry> { $0.establishmentID == sid })
    }

    var body: some View {
        let summary = FinanceSnapshot.make(shop: shop.id, month: month,
                                           payments: payments, refunds: refunds, expenses: expenses)
        List {
            Section("Période") {
                DatePicker("Mois", selection: $month, displayedComponents: .date)
                Button("Exporter le bilan CSV", systemImage: "square.and.arrow.up") { exporting = true }
            }
            Section("Flux enregistrés") {
                LabeledContent("Encaissements confirmés", value: "\(summary.collected.formatted()) \(shop.currencyCode)")
                LabeledContent("Remboursements remis", value: "−\(summary.refunded.formatted()) \(shop.currencyCode)")
                LabeledContent("Dépenses", value: "−\(summary.expenses.formatted()) \(shop.currencyCode)")
                LabeledContent("Solde net des flux", value: "\(summary.balance.formatted()) \(shop.currencyCode)")
                    .font(.headline)
                LabeledContent("Paiements", value: String(summary.paymentCount))
                Text("Ce solde est une estimation basée uniquement sur les opérations enregistrées. Il ne représente ni le bénéfice comptable ni le solde de votre banque ou Mobile Money.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Par moyen de paiement") {
                if summary.byMethod.isEmpty { Text("Aucun paiement confirmé ce mois.") }
                ForEach(summary.byMethod.indices, id: \.self) { index in
                    let row = summary.byMethod[index]
                    LabeledContent(row.0, value: "\(row.1.formatted()) \(shop.currencyCode)")
                }
            }
            Section("Par catégorie de dépense") {
                if summary.byExpense.isEmpty { Text("Aucune dépense active ce mois.") }
                ForEach(summary.byExpense.indices, id: \.self) { index in
                    let row = summary.byExpense[index]
                    LabeledContent(row.0, value: "\(row.1.formatted()) \(shop.currencyCode)")
                }
            }
            if !exportError.isEmpty { Text(exportError).foregroundStyle(.red) }
        }
        .navigationTitle("Bilan de trésorerie")
        .scrollContentBackground(.hidden).background(COVITheme.cream)
        .fileExporter(isPresented: $exporting,
            document: COVICSVDocument(Self.export(snapshot: summary, month: month, currency: shop.currencyCode)),
            contentType: .commaSeparatedText, defaultFilename: "COVI-bilan-mensuel") { result in
                if case .failure(let fault) = result { exportError = fault.localizedDescription }
            }
    }

    static func export(snapshot: FinanceSnapshot, month: Date, currency: String) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: month)
        let period = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        var rows: [[COVICSV.Cell]] = [
            [.text("Encaissements"), .text("Confirmés"), .money(snapshot.collected)],
            [.text("Remboursements"), .text("Remis"), .money(snapshot.refunded)],
            [.text("Dépenses"), .text("Actives"), .money(snapshot.expenses)],
            [.text("Solde des flux"), .text("Ni bénéfice ni solde bancaire"), .money(snapshot.balance)]
        ]
        rows += snapshot.byMethod.map { [.text("Paiement"), .text($0.0), .money($0.1)] }
        rows += snapshot.byExpense.map { [.text("Dépense"), .text($0.0), .money($0.1)] }
        let tabular: [[COVICSV.Cell]] = rows.map { [.text(period), .text(currency)] + $0 }
        return COVICSV.encode(headers: ["Période", "Devise", "Type", "Libellé", "Montant"], rows: tabular)
    }
}

struct ExpenseSpace: View {
    let shop: Establishment
    let actor: UUID
    let canCancel: Bool
    @Environment(\.modelContext) private var context
    @Query private var expenses: [ExpenseEntry]
    @State private var month = Date()
    @State private var showingAdd = false
    @State private var exporting = false
    @State private var cancelling: UUID?
    @State private var error = ""

    init(shop: Establishment, actor: UUID, canCancel: Bool) {
        self.shop = shop; self.actor = actor; self.canCancel = canCancel
        let shopID = shop.id
        _expenses = Query(filter: #Predicate<ExpenseEntry> { $0.establishmentID == shopID },
                          sort: \.spentAt, order: .reverse)
    }

    var body: some View {
        let monthRows = expenses.filter { Calendar.current.isDate($0.spentAt, equalTo: month, toGranularity: .month) }
        let total = monthRows.filter { $0.voidedAt == nil }
            .reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) }
        List {
            Section("Période") {
                DatePicker("Mois", selection: $month, displayedComponents: .date)
                LabeledContent("Dépenses confirmées", value: "\(total.formatted()) \(shop.currencyCode)")
                    .font(.headline)
                Button("Exporter le journal CSV", systemImage: "square.and.arrow.up") { exporting = true }
                Text("Le fichier peut contenir vos notes privées. Ne le partagez qu’avec une personne de confiance.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Journal des dépenses") {
                if monthRows.isEmpty {
                    ContentUnavailableView("Aucune dépense", systemImage: "wallet.pass",
                        description: Text("Ajoutez vos frais de loyer, transport, salaire ou exploitation."))
                }
                ForEach(monthRows) { expense in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(expense.category).font(.headline)
                            Spacer()
                            Text("\(expense.amountMinor) \(shop.currencyCode)")
                        }
                        Text(expense.spentAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                        if !expense.note.isEmpty { Text(expense.note).font(.subheadline) }
                        if expense.voidedAt != nil {
                            Label("Annulée · historique conservé", systemImage: "xmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .swipeActions {
                        if canCancel && expense.voidedAt == nil {
                            Button("Annuler", role: .destructive) { cancelling = expense.id }
                        }
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Dépenses")
        .toolbar { Button("Ajouter", systemImage: "plus") { showingAdd = true } }
        .sheet(isPresented: $showingAdd) { ExpenseForm(shop: shop, actor: actor) }
        .fileExporter(isPresented: $exporting, document: COVICSVDocument(Self.export(monthRows)),
            contentType: .commaSeparatedText, defaultFilename: "COVI-depenses") { result in
                if case .failure(let fault) = result { error = fault.localizedDescription }
            }
        .confirmationDialog("Annuler cette dépense ?", isPresented: Binding(
            get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }
        )) {
            Button("Confirmer l’annulation", role: .destructive) {
                guard let id = cancelling, let row = expenses.first(where: { $0.id == id }) else { return }
                do { try ExpenseLedger.void(row, shop: shop, actor: actor, context: context) }
                catch { self.error = error.localizedDescription }
                cancelling = nil
            }
        } message: {
            Text("Le mouvement sera exclu des totaux, mais restera dans votre historique.")
        }
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
    }

    static func export(_ expenses: [ExpenseEntry]) -> String {
        let rows: [[COVICSV.Cell]] = expenses.map { entry in
            [.text(entry.spentAt.formatted(.iso8601)), .text(entry.category),
             .number(String(entry.amountMinor)),
             .text(entry.voidedAt == nil ? "Active" : "Annulée"), .text(entry.note)]
        }
        return COVICSV.encode(headers: ["Date", "Catégorie", "Montant", "État", "Note"], rows: rows)
    }
}

private struct ExpenseForm: View {
    let shop: Establishment
    let actor: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var category = ExpenseCategory.all[0]
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Catégorie", selection: $category) {
                    ForEach(ExpenseCategory.all, id: \.self) { Text($0) }
                }
                TextField("Montant en " + shop.currencyCode, text: $amount).keyboardType(.numberPad)
                DatePicker("Date de la dépense", selection: $date, in: ...Date.now,
                           displayedComponents: .date)
                TextField("Note facultative", text: $note, axis: .vertical)
                Button("Enregistrer la dépense") {
                    do {
                        try ExpenseLedger.record(shop: shop, actor: actor, category: category,
                            amount: Int64(amount) ?? 0, date: date, note: note, context: context)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled((Int64(amount) ?? 0) <= 0)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Nouvelle dépense")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct HelpPrivacyView: View {
    let kind: BusinessKind

    var body: some View {
        List {
            Section("Bien démarrer") {
                Label("1. Ajoutez vos articles, votre carte ou vos prestations.", systemImage: "square.and.pencil")
                Label("2. Enregistrez vos ventes ou rendez-vous sur l’iPhone.", systemImage: "checklist")
                Label("3. Confirmez les paiements lorsque l’argent est réellement reçu en caisse.",
                      systemImage: "checkmark.shield")
            }
            Section("Votre activité") {
                switch kind {
                case .boutique:
                    Text("Utilisez Stock pour créer les produits et suivre les arrivages, puis Vendre pour encaisser.")
                case .restaurant:
                    Text("Configurez les tables et les menus. Le personnel envoie les plats en cuisine et confirme l’addition en caisse.")
                case .salon:
                    Text("Ajoutez d’abord votre équipe et vos prestations depuis Plus, puis créez les fiches clients et les rendez-vous.")
                }
            }
            Section("Paiements") {
                Text("COVI ne retire aucun argent des comptes clients. Espèces et Mobile Money sont enregistrés uniquement après confirmation humaine.")
                Text("Le service est gratuit : aucun abonnement ni achat intégré.")
            }
            Section("Dépenses et trésorerie") {
                Text("Dans Plus, les responsables peuvent saisir le loyer, les frais et les salaires du commerce.")
                Text("Le bilan mensuel montre les encaissements confirmés, les remboursements et les dépenses. Ce n’est pas un bénéfice comptable.")
                Text("Une dépense incorrecte est annulée, jamais effacée sans trace.")
            }
            Section("Confidentialité") {
                Label("Données locales enregistrées avec SwiftData.", systemImage: "iphone")
                Label("Identité locale enregistrée dans le trousseau sécurisé iOS.", systemImage: "lock")
                Label("Le compte Apple utilise AuthenticationServices.", systemImage: "person.crop.circle")
                Text("Le répertoire, les reçus confirmés et les dépenses peuvent être synchronisés dans le CloudKit privé de votre compte iCloud. Les stocks, fiches clients et commandes en cours restent sur cet iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Aide et confidentialité")
        .scrollContentBackground(.hidden).background(COVITheme.cream)
    }
}

struct CommerceReceiptHistory: View {
    let shop: Establishment
    @Query private var orders: [CommerceOrder]

    init(shop: Establishment) {
        self.shop = shop
        let id = shop.id
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id },
                        sort: \.createdAt, order: .reverse)
    }

    var body: some View {
        let completed = orders.filter { $0.state == .completed && $0.totalMinor > 0 }
        List {
            if completed.isEmpty {
                ContentUnavailableView("Aucun reçu", systemImage: "receipt",
                                       description: Text("Les ventes confirmées en caisse apparaîtront ici."))
            }
            ForEach(completed) { order in
                NavigationLink {
                    ReceiptDetail(order: order, shop: shop)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("\(order.totalMinor) \(shop.currencyCode) · " +
                             String(order.id.uuidString.prefix(8)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Historique des reçus")
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
    }
}

/// Carte de visite hors ligne, partageable sans publication de données sur un serveur.
struct LocalShopCard: View {
    let shop: Establishment
    private var details: String {
        let label: String
        switch shop.kind {
        case .boutique: label = "Boutique"
        case .restaurant: label = "Restaurant"
        case .salon: label = "Salon de coiffure"
        }
        return "\(shop.name)\n\(label) · \(shop.city)\nFiche créée avec COVI"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: shop.kind == .restaurant ? "fork.knife" :
                    shop.kind == .salon ? "scissors" : "bag")
                    .font(.system(size: 44))
                    .foregroundStyle(COVITheme.navy)
                    .accessibilityHidden(true)
                Text(shop.name).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Label(shop.city, systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Text("Cette fiche est accessible hors ligne. Le QR code partage uniquement le nom, l’activité et la ville.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let qr = qrImage {
                    Image(decorative: qr, scale: 1)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 240).padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("QR code de la fiche \(shop.name)")
                }
                ShareLink(item: details) {
                    Label("Partager la fiche", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(COVITheme.navy)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(COVITheme.cream)
        .navigationTitle("Fiche établissement")
    }

    private var qrImage: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(details.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}
