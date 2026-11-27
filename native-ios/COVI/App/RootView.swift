import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    private enum SpaceSheet: String, Identifiable {
        case spaces, setup
        var id: Self { self }
    }

    @Query(sort: \Establishment.name) private var establishments: [Establishment]
    @Query private var memberships: [Membership]
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selectedID: UUID?
    @State private var spaceSheet: SpaceSheet?
    private func selectShop(_ id: UUID, for account: UUID) {
        pinManager.lock()
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: "covi.shop." + account.uuidString)
    }
    @State private var pinManager: PINManager
    @State private var restoring = true
    @State private var importingDirectory = false
    @State private var directoryError = ""

    init(pinManager: PINManager? = nil) {
        _pinManager = State(initialValue: pinManager ?? PINManager())
    }

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
                        let headerLayout = textSize.isAccessibilitySize
                            ? AnyLayout(HStackLayout(spacing: 0))
                            : AnyLayout(VStackLayout(spacing: 0))
                        headerLayout {
                            COVIShopHeader(shop: shop) { spaceSheet = .spaces }
                            if role == .owner {
                                ShopSyncStatus(shop: shop)
                                    .id(shop.id)
                                    .padding(.trailing, 16)
                                    .padding(.leading, textSize.isAccessibilitySize ? 0 : 16)
                                    .padding(.bottom, textSize.isAccessibilitySize ? 0 : 5)
                            }
                        }
                        DynamicTabView(establishment: shop, accountID: account, role: role,
                                       pinManager: pinManager, onSwitchShop: { spaceSheet = .spaces })
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
                .sheet(item: $spaceSheet) { page in
                    switch page {
                    case .setup:
                        EstablishmentSetup(account: account, onCancel: { spaceSheet = nil }) { id in
                            selectShop(id, for: account)
                            spaceSheet = nil
                        }
                    case .spaces:
                        COVISpaces(account: account, accountName: session.displayName, activeID: activeID,
                                   onSelect: { id in
                            guard let candidate = establishments.first(where: { $0.id == id }),
                                  role(candidate, account) != nil else { return }
                            selectShop(id, for: account)
                            spaceSheet = nil
                        }, onAdd: {
                            guard EstablishmentPolicy.canCreate(owner: account, in: establishments) else { return }
                            spaceSheet = .setup
                        })
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
        .onChange(of: session.accountID) { _, _ in
            pinManager.lock()
            selectedID = nil
            spaceSheet = nil
        }
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

@MainActor
private struct COVIShopHeader: View {
    let shop: Establishment
    let onOpenSpaces: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    var body: some View {
        let (activity, symbol) = switch shop.kind {
        case .boutique: ("Boutique", "storefront")
        case .restaurant: ("Restaurant", "fork.knife")
        case .salon: ("Salon de coiffure", "scissors")
        }
        return Button(action: onOpenSpaces) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    if !textSize.isAccessibilitySize {
                        Text("COVI").font(.caption.weight(.bold))
                    }
                    Text(shop.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !textSize.isAccessibilitySize {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .foregroundStyle(COVITheme.navy)
            .background(COVITheme.cream)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mes espaces")
        .accessibilityValue("\(shop.name), \(activity)")
        .accessibilityAddTraits(.isButton)
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, [.shopHeader, .salonAgenda].contains(diagnostics.scenario),
               diagnostics.shop.id == shop.id {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }
}

@MainActor
struct COVISpaces: View {
    let account: UUID
    let accountName: String
    let activeID: UUID?
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    @Query(sort: \Establishment.name) private var establishments: [Establishment]
    @Query private var memberships: [Membership]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    private var owned: [Establishment] {
        var shops = establishments.filter { $0.ownerID == account && !$0.archived }
        if let index = shops.firstIndex(where: { $0.id == activeID }), index > 0 {
            let selected = shops.remove(at: index)
            shops.insert(selected, at: 0)
        }
        return shops
    }

    var body: some View {
        let owned = self.owned
        let shared = establishments.compactMap { shop -> (shop: Establishment, role: StaffRole)? in
            guard shop.ownerID != account,
                  let role = StaffAccess.role(for: account, in: shop, memberships: memberships)
            else { return nil }
            return (shop, role)
        }
        let remaining = max(0, EstablishmentPolicy.maximumActivePerOwner - owned.count)
        let canAdd = EstablishmentPolicy.canCreate(owner: account, in: establishments)
        let addButton = COVIButton("Ajouter un établissement\n\(remaining == 1 ? "1 place restante" : "\(remaining) places restantes")",
                                   systemImage: "plus", role: .secondary, action: onAdd)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image("WelcomeMark")
                            .resizable().scaledToFit()
                            .frame(width: 120, height: 52)
                            .accessibilityLabel("COVI, Commerce & Vie")
                        Spacer()
                        if !accountName.isEmpty {
                            let initials = String(accountName.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
                            Text(initials)
                                .font(.subheadline.bold())
                                .padding(10)
                                .background(COVITheme.champagne, in: Circle())
                                .accessibilityLabel(accountName)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mes espaces").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Basculez d’un établissement à l’autre sans vous déconnecter.")
                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Établissements détenus (\(owned.count) / \(EstablishmentPolicy.maximumActivePerOwner) maximum)")
                            .font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                        ForEach(owned) { shop in
                            spaceButton(shop, role: .owner)
                        }
                    }
                    if !shared.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Accès collaborateur")
                                .font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                            ForEach(shared, id: \.shop.id) { space in
                                spaceButton(space.shop, role: space.role)
                            }
                        }
                    }
                    if canAdd && textSize.isAccessibilitySize {
                        addButton
                    }
                }
                .foregroundStyle(COVITheme.navy)
                .padding(.horizontal, COVITheme.Metrics.screenPadding)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(COVIBackdrop())
            .safeAreaInset(edge: .bottom) {
                if canAdd && !textSize.isAccessibilitySize {
                    addButton
                        .padding(.horizontal, COVITheme.Metrics.screenPadding)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .background(COVITheme.cream)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func spaceButton(_ shop: Establishment, role: StaffRole) -> some View {
        let selected = shop.id == activeID
        let (activity, symbol) = switch shop.kind {
        case .boutique: ("Boutique", "bag")
        case .restaurant: ("Restaurant", "fork.knife")
        case .salon: ("Salon", "scissors")
        }
        let roleLabel = switch role {
        case .owner: ""
        case .manager: "Responsable"
        case .cashier: "Caissier"
        case .waiter: "Serveur"
        case .kitchen: "Cuisine"
        case .stylist: "Coiffure"
        }
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return Button { onSelect(shop.id) } label: {
            COVICard {
                layout {
                    Image(systemName: symbol)
                        .font(.title2)
                        .frame(width: 58, height: 54)
                        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shop.name).font(.headline)
                        COVIBadge(title: roleLabel.isEmpty ? activity : "\(activity) · \(roleLabel)")
                        Text("\(shop.city) · \(shop.currencyCode)")
                            .font(.caption).foregroundStyle(COVITheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: selected ? "checkmark.circle.fill" : (role == .owner ? "circle" : "person.2"))
                        .font(.title2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(COVITheme.navy)
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius)
                        .strokeBorder(COVITheme.navy, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 36
    private enum Route: Hashable { case register, login }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .accessibilityHidden(true)
                            Text("Gérez vos ventes, votre stock, votre équipe et vos opérations au quotidien, depuis votre iPhone.")
                                .font(.body)
                                .foregroundStyle(COVITheme.secondaryText)
                                .frame(maxWidth: 284, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.top, 12)
                        WelcomeTradePhoto()
                            .accessibilityLabel("Boutique, Restaurant, Salon de coiffure")
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                VStack(spacing: 12) {
                    COVIButton("Commencer", trailingSystemImage: "arrow.right") { path.append(.register) }
                    COVIButton("Se connecter", role: .secondary) { path.append(.login) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 520)
            }
            .foregroundStyle(COVITheme.navy)
            .background(COVIBackdrop())
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .login: AccountLogin(onRegistration: { path.append(.register) })
                case .register: RegistrationView()
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            guard path.isEmpty else { return }
            if diagnostics?.scenario == .accountLogin {
                path = [.login]
            } else if diagnostics?.scenario == .accountRegistration {
                path = [.register]
            }
        }
#endif
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
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

@MainActor
private struct EstablishmentSetup: View {
    let account: UUID
    var onCancel: (() -> Void)? = nil
    let onCreated: (UUID) -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var name = ""
    @State private var city = ""
    @State private var kind = BusinessKind.boutique
    @State private var currency = "XAF"
    @State private var error = ""
    @State private var saved = false

    var body: some View {
        let disabled = saved || clean(name).isEmpty || clean(city).isEmpty
        let createButton = COVIButton("Créer mon espace") { create() }
            .disabled(disabled)
            .opacity(disabled ? 0.55 : 1)
        let activities = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image("WelcomeMark")
                        .resizable().scaledToFit().frame(width: 134)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("COVI, Commerce & Vie")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Votre établissement")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Renseignez les informations de votre commerce.")
                            .font(.subheadline)
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                    activities {
                        kindCard(.boutique, title: "Boutique", symbol: "bag")
                        kindCard(.restaurant, title: "Restaurant", symbol: "fork.knife")
                        kindCard(.salon, title: "Salon", symbol: "scissors")
                    }
                    detailsCard
                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red)
                    }
                    if textSize.isAccessibilitySize { createButton }
                }
                .padding(COVITheme.Metrics.screenPadding)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(COVIBackdrop())
            .safeAreaInset(edge: .bottom) {
                if !textSize.isAccessibilitySize {
                    createButton
                        .padding(.horizontal, COVITheme.Metrics.screenPadding)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .background(COVITheme.cream)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Retour", action: onCancel)
                    }
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            guard let diagnostics, diagnostics.scenario == .establishmentSetup,
                  account == diagnostics.owner, context.container === diagnostics.container else { return }
            name = "Maison Kongo Style"
            city = "Brazzaville"
            await diagnostics.signalAfterPresentation()
        }
#endif
    }

    private var detailsCard: some View {
        COVICard {
            VStack(alignment: .leading, spacing: 12) {
                detailRow("Nom de l’établissement", symbol: "storefront") {
                    TextField("Nom de l’établissement", text: $name, prompt: Text("Ex. Maison Kongo Style"))
                        .textContentType(.organizationName)
                }
                Divider()
                detailRow("Ville", symbol: "mappin.and.ellipse") {
                    TextField("Ville", text: $city, prompt: Text("Ex. Brazzaville"))
                        .textContentType(.addressCity)
                }
                Divider()
                detailRow("Devise", symbol: "banknote") {
                    Menu {
                        Picker("Devise", selection: $currency) {
                            ForEach(SupportedCurrency.options) { option in
                                Text(option.label + " · " + option.code).tag(option.code)
                            }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            let label = SupportedCurrency.options.first { $0.code == currency }?.label ?? currency
                            Text("\(label) · \(currency)")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.bold())
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(COVITheme.blue)
                    }
                    .accessibilityLabel("Devise")
                    .accessibilityValue(currency)
                    Text("La devise est fixée lors de la création, sans conversion automatique.")
                        .font(.caption)
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }
        }
    }

    private func detailRow<Content: View>(_ title: String, symbol: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func kindCard(_ candidate: BusinessKind, title: String, symbol: String) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 8))
        return Button {
            kind = candidate
            HapticService.tap()
        } label: {
            layout {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .foregroundStyle(COVITheme.navy)
            .background(kind == candidate ? COVITheme.champagne : .white,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(kind == candidate ? COVITheme.navy : COVITheme.separator,
                                  lineWidth: kind == candidate ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
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
