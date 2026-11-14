import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @Query(sort: \Establishment.name) private var establishments: [Establishment]
    @Query private var memberships: [Membership]
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    @State private var selectedID: UUID?
    @State private var addingShop = false
    private func selectShop(_ id: UUID, for account: UUID) {
        pinManager.lock()
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: "covi.shop." + account.uuidString)
    }
    @State private var pinManager = PINManager()
    @State private var restoring = true
    @State private var logoutError = false

    private func role(_ shop: Establishment, _ account: UUID) -> StaffRole? {
        guard !shop.archived else { return nil }
        if shop.ownerID == account { return .owner }
        let matches = memberships.filter { $0.accountID == account && $0.establishmentID == shop.id }
        guard matches.count == 1, let membership = matches.first, membership.active,
              let role = StaffRole(rawValue: membership.roleRaw), role != .owner else { return nil }
        return role
    }
    var body: some View {
        Group {
            if restoring { COVILaunch() }
            else if let account = session.accountID {
                let preferred = selectedID ?? UserDefaults.standard.string(forKey: "covi.shop." + account.uuidString).flatMap(UUID.init(uuidString:))
                let shops = establishments.filter { role($0, account) != nil }
                VStack {
                    if let shop = shops.first(where: { $0.id == preferred }) ?? shops.first,
                       let role = role(shop, account) {
                        Picker("Établissement", selection: Binding(get: { shop.id }, set: { selectShop($0, for: account) })) {
                            ForEach(shops) { Text($0.name).tag($0.id) }
                        }
                        if establishments.filter({ $0.ownerID == account && !$0.archived }).count < 3 {
                            Button("Ajouter un établissement") { addingShop = true }
                        }
                        DynamicTabView(establishment: shop, accountID: account, role: role, pinManager: pinManager)
                            .id("\(account)-\(shop.id)-\(role.rawValue)")
                        if role == .owner { ShopSyncStatus(shop: shop).id(shop.id) }
                    } else { EstablishmentSetup(account: account) { selectShop($0, for: account) }.id(account) }
                    Button("Se déconnecter") {
                        pinManager.lock()
                        do { try session.signOut() } catch { logoutError = true }
                    }
                }
                .sheet(isPresented: $addingShop) {
                    EstablishmentSetup(account: account) { id in
                        selectShop(id, for: account)
                        addingShop = false
                    }
                }
            } else { COVIWelcome() }
        }
        .task { if restoring { try? await session.restore(); restoring = false } }
        .onChange(of: phase) { _, phase in if phase != .active { pinManager.lock() } }
        .onChange(of: session.accountID) { _, _ in pinManager.lock(); selectedID = nil; addingShop = false }
        .alert("Effacement de la session locale impossible", isPresented: $logoutError) { Button("OK") {} }
    }
}

private struct COVILaunch: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.055, green: 0.14, blue: 0.20)
            Image("LaunchMark")
                .resizable().scaledToFit().frame(maxWidth: 205)
                .accessibilityLabel("COVI, Commerce & Vie")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Wave().fill(LinearGradient(colors: [COVITheme.sand, .brown], startPoint: .leading, endPoint: .trailing))
                .frame(height: 130)
        }.ignoresSafeArea()
    }

    private struct Wave: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: rect.height * 0.28))
                path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.5),
                              control1: CGPoint(x: rect.width * 0.4, y: -20),
                              control2: CGPoint(x: rect.width * 0.58, y: rect.height))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.addLine(to: CGPoint(x: 0, y: rect.height))
                path.closeSubpath()
            }
        }
    }
}

private struct COVIWelcome: View {
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 36
    private enum Route: Hashable { case register, login }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image("WelcomeMark").resizable().scaledToFit().frame(width: 144)
                            .accessibilityLabel("COVI, Commerce & Vie")
                            .padding(.bottom, 8)
                        Text("Le système\nd’exploitation de\nvotre commerce")
                            .font(.system(size: headingSize, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Capsule().fill(COVITheme.sand).frame(width: 62, height: 5)
                        Text("Gérez vos ventes, votre stock, votre équipe et vos opérations au quotidien, depuis votre iPhone.")
                            .font(.body)
                            .frame(maxWidth: 284, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
                    Image("WelcomeTrades").resizable().scaledToFit()
                        .accessibilityLabel("Boutique, Restaurant, Salon de coiffure")
                }.frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    COVIButton("Commencer →") { path.append(.register) }
                    COVIButton("Se connecter", role: .secondary) { path.append(.login) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 520)
                .background(COVITheme.cream)
            }
            .foregroundStyle(COVITheme.navy).background(COVITheme.cream)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .login: AccountLogin().navigationTitle("Se connecter")
                case .register: RegistrationView()
                }
            }
        }
    }
}

private struct EstablishmentSetup: View {
    let account: UUID
    let onCreated: (UUID) -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var city = ""
    @State private var kind = BusinessKind.boutique
    @State private var currency = "XAF"
    @State private var error = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations de l’établissement") {
                    Picker("Activité", selection: $kind) {
                        Text("Boutique").tag(BusinessKind.boutique)
                        Text("Restaurant").tag(BusinessKind.restaurant)
                        Text("Salon").tag(BusinessKind.salon)
                    }.pickerStyle(.segmented)
                    TextField("Nom de l’établissement", text: $name)
                    TextField("Ville", text: $city)
                    Picker("Devise", selection: $currency) {
                        Text("XAF").tag("XAF")
                        Text("XOF").tag("XOF")
                    }
                }
                COVIButton("Créer mon espace") { create() }
                    .disabled(saved || clean(name).isEmpty || clean(city).isEmpty)
                if !error.isEmpty { Text(error) }
            }
            .scrollContentBackground(.hidden)
            .background(COVITheme.cream)
            .navigationTitle("Votre établissement")
        }
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor private func create() {
        guard !saved, session.accountID == account, !clean(name).isEmpty, !clean(city).isEmpty else { return }
        do {
            let owner = account
            let count = try context.fetchCount(FetchDescriptor<Establishment>(predicate: #Predicate {
                $0.ownerID == owner && !$0.archived
            }))
            guard count < 3 else { error = "Trois établissements sont déjà actifs sur cet appareil."; return }
            let shop = Establishment(ownerID: account, name: clean(name), kind: kind, city: clean(city), currencyCode: currency)
            try context.transaction {
                context.insert(shop)
                context.insert(Membership(accountID: account, establishmentID: shop.id, role: .owner))
            }
            saved = true
            onCreated(shop.id)
        } catch { error = "La création a échoué. Vous pouvez réessayer." }
    }
}
