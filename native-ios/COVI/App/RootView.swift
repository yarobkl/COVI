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
            if restoring { ProgressView() }
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
            } else { AccountLogin() }
        }
        .task { if restoring { try? await session.restore(); restoring = false } }
        .onChange(of: phase) { _, phase in if phase != .active { pinManager.lock() } }
        .onChange(of: session.accountID) { _, _ in pinManager.lock(); selectedID = nil }
        .alert("Effacement de la session locale impossible", isPresented: $logoutError) { Button("OK") {} }
    }
}
