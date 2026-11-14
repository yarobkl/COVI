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
    @State private var devices: [Device] = []
    @State private var currency = "XAF"
    @State private var currencyPIN = false
    @State private var revoke = false
    @State private var message = ""
    struct Device: Decodable, Identifiable {
        let id: UUID
        let agent: String
        let seen: String?
        let current_device: Bool
    }
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
            }
            Section("Sessions du compte") {
                ForEach(devices) { d in
                    VStack(alignment: .leading) {
                        Text(d.current_device ? "Session actuelle" : d.agent)
                        if let seen = d.seen { Text(seen).font(.caption) }
                    }
                }
                Button("Déconnecter les autres sessions", role: .destructive) { revoke = true }
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
        }.navigationTitle("Paramètres système").task { currency = shop.currencyCode; await refresh() }
        .confirmationDialog("Déconnecter tous les autres appareils de ce compte ?", isPresented: $revoke) {
            Button("Déconnecter", role: .destructive) { Task { await disconnect() } }
        }
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
        guard let token = session.accessToken else { return }
        do {
            let data = try await SystemAPI.call("/rest/v1/rpc/covi_my_devices", method: "POST", token: token, body: [:])
            devices = try JSONDecoder().decode([Device].self, from: data)
        } catch { devices = []; message = "Liste des sessions indisponible." }
    }
    func disconnect() async {
        guard let token = session.accessToken else { return }
        do {
            _ = try await SystemAPI.call("/auth/v1/logout?scope=others", method: "POST", token: token)
            db.insert(MaintenanceEntry("Autres sessions déconnectées", actor: actor, shop: shop.id))
            try db.save()
            await refresh()
        } catch { message = "Déconnexion ou journalisation impossible." }
    }
}
