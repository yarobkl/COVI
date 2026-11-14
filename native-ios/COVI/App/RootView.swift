import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    @Query(sort: \Establishment.name) private var establishments: [Establishment]
    @Query private var memberships: [Membership]
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    @State private var selectedID: UUID?
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
                let shops = establishments.filter { role($0, account) != nil }
                VStack {
                    if let shop = shops.first(where: { $0.id == selectedID }) ?? shops.first,
                       let role = role(shop, account) {
                        Picker("Établissement", selection: Binding(get: { shop.id }, set: { pinManager.lock(); selectedID = $0 })) {
                            ForEach(shops) { Text($0.name).tag($0.id) }
                        }
                        DynamicTabView(establishment: shop, accountID: account, role: role, pinManager: pinManager)
                            .id("\(account)-\(shop.id)-\(role.rawValue)")
                        if role == .owner { ShopSyncStatus(shop: shop).id(shop.id) }
                    } else { ContentUnavailableView("Aucun établissement accessible", systemImage: "storefront") }
                    Button("Se déconnecter") {
                        pinManager.lock()
                        do { try session.signOut() } catch { logoutError = true }
                    }
                }
            } else { COVIWelcome() }
        }
        .task { if restoring { try? await session.restore(); restoring = false } }
        .onChange(of: phase) { _, phase in if phase != .active { pinManager.lock() } }
        .onChange(of: session.accountID) { _, _ in pinManager.lock(); selectedID = nil }
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
