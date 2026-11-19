import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

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
    @Environment(AppSession.self) private var session
    @State private var confirmingSignOut = false
    @State private var signOutFailed = false

    var body: some View {
        List {
            Section("Établissement") {
                Text(shop.name).font(.headline)
                Text(shop.city)
                NavigationLink("Fiche à partager") { LocalShopCard(shop: shop) }
            }
            Section("Votre espace") {
                NavigationLink("Paramètres système") { SystemSettings(shop: shop, actor: actor, pin: pin) }
                NavigationLink("Historique des reçus") { CommerceReceiptHistory(shop: shop) }
                if role == .owner || role == .manager {
                    NavigationLink("Dépenses du commerce") {
                        ExpenseSpace(shop: shop, actor: actor, canCancel: role == .owner)
                    }
                    NavigationLink("Bilan de trésorerie") { FinanceOverview(shop: shop) }
                }
                NavigationLink("Aide et confidentialité") { HelpPrivacyView(kind: shop.kind) }
                if role == .owner {
                    NavigationLink("Paramètres propriétaire") { OwnerSettings(shop: shop, pinManager: pin) }
                }
                if shop.kind == .salon && (role == .owner || role == .manager) {
                    NavigationLink("Catalogue et rapports salon") {
                        SalonSpace(shop: shop, tab: .more, actor: actor, role: role, pin: pin)
                    }
                }
            }
            Section {
                LabeledContent("Abonnement", value: "Gratuit")
                Text("Les données du commerce sont gérées sur iPhone, sans base de données web.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Compte") {
                Button(role: .destructive) { confirmingSignOut = true } label: {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Plus")
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
        .confirmationDialog("Se déconnecter de COVI ?", isPresented: $confirmingSignOut) {
            Button("Se déconnecter", role: .destructive) {
                do { try session.signOut() }
                catch { signOutFailed = true }
            }
        } message: {
            Text("Vos établissements et vos opérations enregistrées restent sur cet iPhone.")
        }
        .alert("Déconnexion impossible", isPresented: $signOutFailed) {
            Button("OK") {}
        } message: {
            Text("Le trousseau iOS n'a pas permis d'effacer la session active.")
        }
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
        }
        .navigationTitle("Bilan de trésorerie")
        .scrollContentBackground(.hidden).background(COVITheme.cream)
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
                TextField("Montant en FCFA", text: $amount).keyboardType(.numberPad)
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
                Text("Le répertoire des établissements et les reçus confirmés peuvent être synchronisés dans le CloudKit privé de votre compte iCloud. Les stocks, fiches clients et commandes en cours restent sur cet iPhone.")
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
