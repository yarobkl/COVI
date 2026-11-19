import SwiftUI
import SwiftData
import CloudKit

@MainActor
struct SystemSettings: View {
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var db
    @Query private var entries: [MaintenanceEntry]
    @State private var cloud = "Vérification en cours"
    @State private var currency = "XAF"
    @State private var profileName = ""
    @State private var currencyPIN = false
    @State private var message = ""
    init(shop: Establishment, actor: UUID, pin: PINManager) {
        self.shop = shop; self.actor = actor; self.pin = pin
        let id = shop.id, user = actor
        _entries = Query(filter: #Predicate<MaintenanceEntry> { $0.shop == id && $0.actor == user }, sort: \.date, order: .reverse)
    }
    var body: some View {
        Form {
            Section("CloudKit") {
                LabeledContent("Compte iCloud", value: cloud)
                Button("Vérifier la connexion") { Task { await refresh() } }
                Text("La connexion iCloud est gérée par iOS. COVI ne dépend d’aucune base de données web.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Identité") {
                LabeledContent("Mode", value: session.usesAppleAccount ? "Connexion Apple" : "Sur cet appareil")
                TextField("Nom du profil", text: $profileName).textContentType(.name)
                Button("Enregistrer le nom") {
                    do {
                        try session.updateDisplayName(profileName)
                        if let owner = session.accountID,
                           let profile = try db.fetch(FetchDescriptor<Account>(
                            predicate: #Predicate { $0.id == owner })).first {
                            profile.fullName = session.displayName
                            try db.save()
                        }
                        message = "Profil actualisé."
                    } catch { db.rollback(); message = "Impossible de modifier le nom." }
                }
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          profileName == session.displayName)
                Text("La déconnexion à distance d'autres appareils n'est pas disponible sans service de gestion de sessions.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Devise de l’établissement") {
                Text("Devise actuelle · " + shop.currencyCode)
                if actor == shop.ownerID {
                    Picker("Franc CFA", selection: $currency) { Text("CEMAC · XAF").tag("XAF"); Text("UEMOA · XOF").tag("XOF") }
                    Button("Appliquer") { currencyPIN = true }.disabled(currency == shop.currencyCode)
                }
            }
            Section("Journal local de maintenance") {
                ForEach(entries.prefix(100)) { entry in
                    VStack(alignment: .leading) { Text(entry.action); Text(entry.date.formatted()).font(.caption) }
                }
            }
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle("Paramètres système")
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
        .task { currency = shop.currencyCode; profileName = session.displayName; await refresh() }
        .sheet(isPresented: $currencyPIN) {
            PINEntryView(pinManager: pin, scope: .master(ownerID: shop.ownerID)) { ok in
                currencyPIN = false
                guard ok, session.accountID == shop.ownerID, !shop.archived else { return }
                do {
                    let id = shop.id
                    let orders = FetchDescriptor<CommerceOrder>(predicate: #Predicate { $0.establishmentID == id })
                    let items = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.establishmentID == id })
                    guard try db.fetchCount(orders) == 0, try db.fetchCount(items) == 0 else {
                        message = "Le catalogue ou les ventes utilisent déjà la devise actuelle."; return
                    }
                    shop.currencyCode = currency
                    shop.updatedAt = .now
                    db.insert(MaintenanceEntry("Devise configurée · " + currency, actor: actor, shop: id))
                    try db.save(); message = "Devise enregistrée."
                } catch { db.rollback(); message = "Échec de l’enregistrement." }
            }
        }
    }
    func refresh() async {
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available: cloud = "Disponible"
            case .noAccount: cloud = "Aucun compte"
            case .restricted: cloud = "Accès restreint"
            default: cloud = "Indisponible"
            }
        } catch { cloud = "Vérification impossible" }
    }
}
