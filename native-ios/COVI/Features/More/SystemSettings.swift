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
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var confirmingSignOut = false
    @State private var signOutFailed = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                COVISectionTitle("Sécurité de caisse partagée")
                securityCard
                COVISectionTitle("Établissement actif (\(shop.name))")
                establishmentCard
                Button(role: .destructive) { confirmingSignOut = true } label: {
                    Label("Déconnecter le compte principal", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.red)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                COVISectionTitle("Identité")
                identityCard
                if !entries.isEmpty {
                    COVISectionTitle("Journal local de maintenance")
                    COVICard {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entries.prefix(100)) { entry in
                                VStack(alignment: .leading) {
                                    Text(entry.action)
                                    Text(entry.date.formatted()).font(.caption)
                                }
                            }
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.footnote)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
        }
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .background(COVIBackdrop())
        .task {
            currency = shop.currencyCode
            profileName = session.displayName
#if DEBUG && targetEnvironment(simulator)
            if let diagnostics, diagnostics.scenario == .salonSettings {
                cloud = "Compte iCloud non vérifié"
                await diagnostics.signalAfterPresentation()
                return
            }
#endif
            await refresh()
        }
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
            Text("Le trousseau iOS n’a pas permis d’effacer la session active.")
        }
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
    private var securityCard: some View {
        COVICard {
            VStack(spacing: 6) {
                COVIIconRow(symbol: "lock", title: "Verrouillage automatique (PIN)",
                    detail: "Après \(Int(pin.inactivityTimeout / 60)) min d’inactivité", accessory: nil)
                if actor == shop.ownerID {
                    Divider()
                    NavigationLink { OwnerSettings(shop: shop, pinManager: pin) } label: {
                        COVIIconRow(symbol: "circle.grid.3x3", title: "Codes PIN et accès", detail: nil)
                    }
                }
                Divider()
                COVIIconRow(symbol: "shield", title: "Remboursements",
                    detail: "PIN propriétaire s’il est configuré", accessory: nil)
            }
        }
    }

    private var establishmentCard: some View {
        COVICard {
            VStack(alignment: .leading, spacing: 8) {
                COVIIconRow(symbol: "mappin.and.ellipse", title: "Ville et devise",
                    detail: "\(shop.city) · \(shop.currencyCode)", accessory: nil)
                Divider()
                COVIIconRow(symbol: "creditcard", title: "Moyens de règlement externes",
                    detail: Tender.allCases.map(\.rawValue).joined(separator: ", "), accessory: nil)
                Divider()
                COVIIconRow(symbol: "icloud", title: "Stockage local et iCloud",
                    detail: cloud, accessory: nil)
                Button("Vérifier la connexion iCloud") { Task { await refresh() } }
                    .font(.footnote.weight(.semibold))
                if actor == shop.ownerID {
                    Divider()
                    Picker("Devise", selection: $currency) {
                        ForEach(SupportedCurrency.options) { option in
                            Text(option.label + " · " + option.code).tag(option.code)
                        }
                    }
                    Text("La devise est verrouillée dès qu’un produit, une vente, un arrivage ou une dépense l’utilise.")
                        .font(.footnote).foregroundStyle(COVITheme.secondaryText)
                    if currency != shop.currencyCode {
                        Button("Appliquer la devise") { currencyPIN = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var identityCard: some View {
        COVICard {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Mode", value: session.usesAppleAccount ? "Connexion Apple" : "Sur cet appareil")
                TextField("Nom du profil", text: $profileName)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
                Button("Enregistrer le nom") { saveProfileName() }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              profileName == session.displayName)
            }
        }
    }

    private func saveProfileName() {
        do {
            try session.updateDisplayName(profileName)
            if let owner = session.accountID,
               let profile = try db.fetch(FetchDescriptor<Account>(
                    predicate: #Predicate { $0.id == owner })).first {
                profile.fullName = session.displayName
                try db.save()
            }
            profileName = session.displayName
            message = "Profil actualisé."
        } catch {
            db.rollback()
            message = "Impossible de modifier le nom."
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
