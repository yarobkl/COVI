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
            Section("Sécurité de caisse partagée") {
                LabeledContent {
                    Text("Après 2 min")
                } label: {
                    Label("Verrouillage automatique (PIN)", systemImage: "lock")
                }
                if actor == shop.ownerID {
                    NavigationLink { OwnerSettings(shop: shop, pinManager: pin) } label: {
                        Label("Codes PIN et accès", systemImage: "circle.grid.3x3")
                    }
                }
                Label("Le PIN est vérifié pour les opérations de caisse et les actions protégées.",
                      systemImage: "shield.checkered")
                    .font(.footnote).foregroundStyle(COVITheme.secondaryText)
            }
            Section("Stockage local & Sauvegarde iCloud") {
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
            Section("Établissement actif (\(shop.name))") {
                LabeledContent("Ville", value: shop.city)
                Text("Devise actuelle · " + shop.currencyCode)
                if actor == shop.ownerID {
                    Picker("Devise", selection: $currency) {
                        ForEach(SupportedCurrency.options) { option in
                            Text(option.label + " · " + option.code).tag(option.code)
                        }
                    }
                    Text("La devise ne peut plus être modifiée une fois le catalogue ou une vente créé. Les montants ne sont jamais convertis.")
                        .font(.footnote).foregroundStyle(.secondary)
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
        .navigationTitle("Paramètres")
        .scrollContentBackground(.hidden)
        .background(COVIBackdrop())
        .task { currency = shop.currencyCode; profileName = session.displayName; await refresh() }
        .sheet(isPresented: $currencyPIN) {
            PINEntryView(pinManager: pin, scope: .master(ownerID: shop.ownerID)) { ok in
                currencyPIN = false
                guard ok, session.accountID == shop.ownerID, !shop.archived,
                      SupportedCurrency.allows(currency) else { return }
                do {
                    let id = shop.id
                    guard try SupportedCurrency.mayChange(shop, to: currency, db: db) else {
                        message = "Des produits, ventes, arrivages ou dépenses utilisent déjà cette devise. Aucun montant historique ne sera reconverti."; return
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
