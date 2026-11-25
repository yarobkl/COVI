import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @Query(sort: \Establishment.name) private var establishments: [Establishment]
    @Query private var memberships: [Membership]
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var selectedID: UUID?
    @State private var addingShop = false
    @State private var showingSpaces = false
    private func selectShop(_ id: UUID, for account: UUID) {
        pinManager.lock()
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: "covi.shop." + account.uuidString)
    }
    @State private var pinManager = PINManager()
    @State private var restoring = true
    @State private var importingDirectory = false
    @State private var directoryError = ""

    private func role(_ shop: Establishment, _ account: UUID) -> StaffRole? {
        StaffAccess.role(for: account, in: shop, memberships: memberships)
    }
    var body: some View {
        Group {
            if restoring { COVILaunch() }
            else if let account = session.accountID {
                let preferred = selectedID ?? UserDefaults.standard.string(forKey: "covi.shop." + account.uuidString).flatMap(UUID.init(uuidString:))
                let shops = establishments.filter { role($0, account) != nil }
                let activeID = shops.first(where: { $0.id == preferred })?.id ?? shops.first?.id
                VStack(spacing: 0) {
                    if let shop = shops.first(where: { $0.id == preferred }) ?? shops.first,
                       let role = role(shop, account) {
                        HStack(spacing: 10) {
                            Image("WelcomeMark")
                                .resizable().scaledToFit().frame(width: 86, height: 42)
                                .accessibilityLabel("COVI, Commerce & Vie")
                            Spacer(minLength: 4)
                            Button { showingSpaces = true } label: {
                                HStack(spacing: 7) {
                                    Text(shop.name).lineLimit(1)
                                    Image(systemName: "chevron.down").font(.caption.bold())
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(COVITheme.navy)
                                .padding(.horizontal, 12).padding(.vertical, 11)
                                .background(COVITheme.champagne, in: Capsule())
                            }
                            .accessibilityLabel("Mes espaces, établissement actif : \(shop.name)")
                        }
                        .padding(.horizontal, 16)
                        .background(COVITheme.cream)
                        // La synchronisation appartient à l'en-tête de l'espace,
                        // pas à une barre supplémentaire sous les onglets iOS.
                        if role == .owner {
                            ShopSyncStatus(shop: shop)
                                .id(shop.id)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 5)
                        }
                        DynamicTabView(establishment: shop, accountID: account, role: role,
                                       pinManager: pinManager, onSwitchShop: { showingSpaces = true })
                            .id("\(account)-\(shop.id)-\(role.rawValue)")
                    } else if importingDirectory {
                        ContentUnavailableView {
                            Label("Recherche de vos établissements", systemImage: "icloud")
                        } description: {
                            Text("COVI vérifie votre répertoire iCloud privé.")
                        } actions: {
                            ProgressView()
                        }
                    } else {
                        if !directoryError.isEmpty {
                            ContentUnavailableView {
                                Label("iCloud indisponible", systemImage: "icloud.slash")
                            } description: {
                                Text(directoryError)
                            } actions: {
                                Button("Réessayer") { Task { await importDirectory(account) } }
                            }
                        }
                        EstablishmentSetup(account: account) { selectShop($0, for: account) }.id(account)
                    }
                }
                .background(COVITheme.cream)
                .sheet(isPresented: $addingShop) {
                    EstablishmentSetup(account: account) { id in
                        selectShop(id, for: account)
                        addingShop = false
                    }
                }
                .sheet(isPresented: $showingSpaces) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                Image("WelcomeMark").resizable().scaledToFit()
                                    .frame(width: 150).frame(maxWidth: .infinity)
                                Text("Mes espaces")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(COVITheme.navy)
                                Text("Basculez d’un établissement à l’autre sans vous déconnecter.")
                                    .foregroundStyle(COVITheme.secondaryText)
                                COVISectionTitle("Établissements détenus (\(shops.filter { $0.ownerID == account }.count) / \(EstablishmentPolicy.maximumActivePerOwner) maximum)")
                                ForEach(shops.filter { $0.ownerID == account }) { candidate in
                                    spaceButton(candidate, activeID: activeID, account: account)
                                }
                                if shops.contains(where: { $0.ownerID != account }) {
                                    COVISectionTitle("Accès collaborateur")
                                    ForEach(shops.filter { $0.ownerID != account }) { candidate in
                                        spaceButton(candidate, activeID: activeID, account: account)
                                    }
                                }
                                if EstablishmentPolicy.canCreate(owner: account, in: establishments) {
                                    COVIButton("Ajouter un établissement", systemImage: "plus", role: .secondary) {
                                        showingSpaces = false
                                        addingShop = true
                                    }
                                }
                            }
                            .padding(22)
                        }
                        .background(COVIBackdrop())
                        .toolbar { Button("Fermer") { showingSpaces = false } }
                    }
                }
            } else { COVIWelcome() }
        }
        .task { if restoring { try? await session.restore(); restoring = false } }
        .task(id: session.accountID) {
            guard let owner = session.accountID else { return }
            saveNativeProfile(owner)
            if session.usesAppleAccount { await importDirectory(owner) }
        }
        .onChange(of: phase) { _, phase in if phase != .active { pinManager.lock() } }
        .onChange(of: session.accountID) { _, _ in pinManager.lock(); selectedID = nil; addingShop = false }
    }

    private func spaceButton(_ candidate: Establishment, activeID: UUID?, account: UUID) -> some View {
        Button {
            selectShop(candidate.id, for: account)
            showingSpaces = false
        } label: {
            COVICard {
                HStack(spacing: 15) {
                    Image(systemName: candidate.kind == .boutique ? "bag" : candidate.kind == .restaurant ? "fork.knife" : "scissors")
                        .font(.title2).foregroundStyle(COVITheme.navy)
                        .frame(width: 68, height: 68)
                        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(candidate.name).font(.headline).foregroundStyle(COVITheme.navy)
                        COVIBadge(title: candidate.kind == .boutique ? "Boutique" : candidate.kind == .restaurant ? "Restaurant" : "Salon")
                        Text("\(candidate.city) · \(candidate.currencyCode)")
                            .font(.caption).foregroundStyle(COVITheme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: candidate.id == activeID ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(COVITheme.navy)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius)
                .stroke(candidate.id == activeID ? COVITheme.navy : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir \(candidate.name)")
    }

    private func importDirectory(_ account: UUID) async {
        guard session.accountID == account, session.usesAppleAccount else { return }
        importingDirectory = true
        defer { importingDirectory = false }
        do {
            try await CloudShopDirectory.reconcile(owner: account, context: context)
            directoryError = ""
        } catch is CancellationError { return }
        catch {
            directoryError = error.localizedDescription
        }
    }

    private func saveNativeProfile(_ account: UUID) {
        do {
            let profiles = try context.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.id == account }))
            let fullName = session.displayName
            let email = session.email
            if let profile = profiles.first {
                if !fullName.isEmpty { profile.fullName = fullName }
                if !email.isEmpty { profile.email = email }
            } else {
                context.insert(Account(id: account, fullName: fullName,
                                       email: email, phone: ""))
            }
            try context.save()
        } catch {
            context.rollback()
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        Text(dynamicTypeSize.isAccessibilitySize
                            ? "Le système d’exploitation de votre commerce"
                            : "Le système\nd’exploitation de\nvotre commerce")
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
                    WelcomeTradePhoto()
                        .accessibilityLabel("Boutique, Restaurant, Salon de coiffure")
                }.frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    COVIButton("Commencer", systemImage: "arrow.right") { path.append(.register) }
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

/// La photographie source contient une ligne de texte recadrée en haut.
/// Ce cadrage conserve les trois commerces sans superposer la ligne au texte natif.
private struct WelcomeTradePhoto: View {
    private let originalWidth: CGFloat = 490
    private let originalHeight: CGFloat = 284
    private let topTrim: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            Image("WelcomeTrades")
                .resizable()
                .frame(width: geometry.size.width,
                       height: geometry.size.width * originalHeight / originalWidth)
                .offset(y: -geometry.size.width * topTrim / originalWidth)
        }
        .aspectRatio(originalWidth / (originalHeight - topTrim), contentMode: .fit)
        .clipped()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("WelcomeMark")
                        .resizable().scaledToFit().frame(width: 145)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                    HStack(spacing: 12) {
                        COVIBadge(title: "Étape 1 sur 2")
                        GeometryReader { geometry in
                            Capsule().fill(COVITheme.navy.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(COVITheme.navy)
                                        .frame(width: geometry.size.width / 2)
                                }
                        }
                        .frame(height: 8)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Votre établissement")
                            .font(.system(size: 35, weight: .bold))
                            .foregroundStyle(COVITheme.navy)
                        Text("Renseignez les informations de votre commerce.")
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                    HStack(spacing: 10) {
                        kindCard(.boutique, title: "Boutique", symbol: "bag")
                        kindCard(.restaurant, title: "Restaurant", symbol: "fork.knife")
                        kindCard(.salon, title: "Salon", symbol: "scissors")
                    }
                    COVICard {
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Nom de l’établissement", systemImage: "storefront")
                                .font(.subheadline.weight(.semibold))
                            TextField("Ex. Maison Kongo Style", text: $name)
                                .textContentType(.organizationName)
                            Divider()
                            Label("Ville", systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.semibold))
                            TextField("Ex. Brazzaville", text: $city)
                            Divider()
                            Label("Devise", systemImage: "banknote")
                                .font(.subheadline.weight(.semibold))
                            Picker("Devise", selection: $currency) {
                                ForEach(SupportedCurrency.options) { option in
                                    Text(option.label + " · " + option.code).tag(option.code)
                                }
                            }
                            .tint(COVITheme.navy)
                            Text("La devise est fixée lors de la création : aucune conversion automatique.")
                                .font(.caption).foregroundStyle(COVITheme.secondaryText)
                        }
                        .foregroundStyle(COVITheme.navy)
                    }
                    COVIButton("Créer mon espace") { create() }
                        .disabled(saved || clean(name).isEmpty || clean(city).isEmpty)
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }
                .padding(22)
            }
            .background(COVIBackdrop())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func kindCard(_ candidate: BusinessKind, title: String, symbol: String) -> some View {
        Button { kind = candidate; HapticService.tap() } label: {
            VStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 27))
                Text(title).font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.75).lineLimit(1)
            }
            .foregroundStyle(COVITheme.navy)
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.vertical, 10)
            .background(kind == candidate ? COVITheme.champagne : .white,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(kind == candidate ? COVITheme.navy : COVITheme.separator,
                        lineWidth: kind == candidate ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == candidate ? .isSelected : [])
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor private func create() {
        guard !saved, session.accountID == account, !clean(name).isEmpty,
              !clean(city).isEmpty, SupportedCurrency.allows(currency) else { return }
        do {
            let owner = account
            let count = try context.fetchCount(FetchDescriptor<Establishment>(predicate: #Predicate {
                $0.ownerID == owner && !$0.archived
            }))
            guard count < EstablishmentPolicy.maximumActivePerOwner else {
                error = "Trois établissements sont déjà actifs sur cet appareil."
                return
            }
            let shop = Establishment(ownerID: account, name: clean(name), kind: kind, city: clean(city), currencyCode: currency)
            try context.transaction {
                context.insert(shop)
                context.insert(Membership(accountID: account, establishmentID: shop.id, role: .owner))
            }
            saved = true
            onCreated(shop.id)
        } catch { self.error = "La création a échoué. Vous pouvez réessayer." }
    }
}
