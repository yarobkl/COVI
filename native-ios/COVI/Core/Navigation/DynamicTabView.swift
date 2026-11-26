import SwiftUI
import SwiftData

enum BusinessTab: String, Hashable, Identifiable {
    case home, sell, stock, orders, more, service, tables, kitchen, today, agenda, checkout, clients
    var id: Self { self }
    var title: String {
        switch self {
        case .home: "Accueil"; case .sell: "Vendre"; case .stock: "Stock"
        case .orders: "Commandes"; case .more: "Plus"; case .service: "Service"
        case .tables: "Tables"; case .kitchen: "Cuisine"; case .today: "Aujourd’hui"
        case .agenda: "Agenda"; case .checkout: "Caisse"; case .clients: "Clients"
        }
    }
    var symbol: String {
        switch self {
        case .home, .today: "house"; case .sell: "cart"; case .stock: "shippingbox"
        case .orders: "list.clipboard"; case .more: "ellipsis"; case .service: "fork.knife"
        case .tables: "square.grid.2x2"; case .kitchen: "flame"
        case .agenda: "calendar"; case .checkout: "creditcard"; case .clients: "person.2"
        }
    }
}

enum TabPolicy {
    static func tabs(for kind: BusinessKind) -> [BusinessTab] {
        switch kind {
        case .boutique: [.home, .sell, .stock, .orders, .more]
        case .restaurant: [.service, .tables, .kitchen, .more]
        case .salon: [.today, .agenda, .checkout, .clients, .more]
        }
    }
    static func tabs(for kind: BusinessKind, role: StaffRole) -> [BusinessTab] {
        tabs(for: kind).filter { tab in
            switch role {
            case .owner, .manager: true
            case .cashier: [.home, .sell, .orders, .checkout, .today, .more].contains(tab)
            case .waiter: [.service, .tables, .more].contains(tab)
            case .kitchen: [.kitchen, .more].contains(tab)
            case .stylist: [.today, .agenda, .clients, .more].contains(tab)
            }
        }
    }

    static func requiresPIN(_ tab: BusinessTab) -> Bool {
        [.sell, .checkout, .service, .tables, .kitchen].contains(tab)
    }
}

struct DynamicTabView: View {
    let establishment: Establishment
    let accountID: UUID
    let role: StaffRole
    @Bindable var pinManager: PINManager
    let onSwitchShop: () -> Void
    @State private var selected: BusinessTab = .home
    @State private var pending: BusinessTab?
    @State private var showingPIN = false
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    private var tabs: [BusinessTab] { TabPolicy.tabs(for: establishment.kind, role: role) }

    var body: some View {
        TabView(selection: Binding(
            get: { selected },
            set: { requested in
                guard requested != selected else { return }
                if TabPolicy.requiresPIN(requested) && !pinManager.mayOperate(shop: establishment, actor: accountID) {
                    pending = requested
                    showingPIN = true
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { selected = requested }
                    pinManager.touch()
                    HapticService.tap()
                }
            }
        )) {
            ForEach(tabs) { tab in
                NavigationStack {
                    if TabPolicy.requiresPIN(tab) && !pinManager.mayOperate(shop: establishment, actor: accountID) {
                        Button("Déverrouiller") { pending = tab; showingPIN = true }
                    } else if tab == .more {
                        MoreSpace(shop: establishment, actor: accountID, role: role,
                                  pin: pinManager, onSwitchShop: onSwitchShop)
                    } else if establishment.kind == .salon {
                        SalonSpace(shop: establishment, tab: tab, actor: accountID, role: role, pin: pinManager)
                    } else if establishment.kind == .restaurant && [.service, .tables, .kitchen].contains(tab) {
                        RestaurantSpace(shop: establishment, tab: tab, actor: accountID, role: role, pin: pinManager)
                    } else if establishment.kind == .boutique && [.home, .sell, .stock].contains(tab) {
                        BoutiqueSpace(tab: tab, shop: establishment, actor: accountID, pin: pinManager) {
                            if pinManager.mayOperate(shop: establishment, actor: accountID) { selected = .sell }
                            else { pending = .sell; showingPIN = true }
                        }
                    } else if tab == .orders && establishment.kind == .boutique {
                        BoutiqueOrders(shop: establishment)
                    } else {
                        ContentUnavailableView("Section indisponible", systemImage: "exclamationmark.triangle",
                                               description: Text("Vérifiez le type d’établissement sélectionné."))
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .tint(COVITheme.navy)
        .sheet(isPresented: $showingPIN) {
            PINEntryView(pinManager: pinManager, scope: .cashier(staffID: accountID, shopID: establishment.id)) { success in
                showingPIN = false
                if success, let pending { selected = pending }
                pending = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
#if DEBUG && targetEnvironment(simulator)
            selected = tabs[0]
            if let diagnostics, diagnostics.shop.id == establishment.id, diagnostics.owner == accountID,
               role == .owner, pinManager.mayOperate(shop: establishment, actor: accountID) {
                switch diagnostics.scenario {
                case .sale, .checkout: selected = .sell
                case .restaurantTables: selected = .tables
                case .restaurantKitchen: selected = .kitchen
                case .salonCheckout: selected = .checkout
                case .salonReport, .salonMore, .salonSettings, .restaurantReport, .restaurantTeam, .restaurantMenu, .restaurantDrinks: selected = .more
                case .salonToday: selected = .today
                case .salonClients, .salonProfile: selected = .clients
                case .salonAgenda, .salonBooking, .salonBookingConflict: selected = .agenda
                case .welcome, .boutiqueHome, .restaurantTable, .restaurantOrder, .salonCatalog: break
                }
            }
#else
            selected = tabs[0]
#endif
        }
        .onChange(of: establishment.id) { _, _ in
            pinManager.lock()
            selected = tabs[0]
        }
    }
}

private struct BoutiqueOrders: View {
    @Query private var orders: [CommerceOrder]
    let shop: Establishment

    init(shop: Establishment) {
        self.shop = shop
        let id = shop.id
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id },
                        sort: \.createdAt, order: .reverse)
    }

    var body: some View {
        List {
            if orders.isEmpty { ContentUnavailableView("Aucune commande", systemImage: "receipt") }
            ForEach(orders) { order in
                NavigationLink {
                    BoutiqueOrderDetail(order: order, shop: shop)
                } label: {
                    LabeledContent(order.createdAt.formatted(date: .abbreviated, time: .shortened),
                                   value: "\(order.totalMinor) \(shop.currencyCode)")
                }
            }
        }.navigationTitle("Commandes")
    }
}

private struct BoutiqueOrderDetail: View {
    let order: CommerceOrder
    let shop: Establishment
    @Query private var lines: [OrderLine]
    @Query private var items: [CatalogItem]

    init(order: CommerceOrder, shop: Establishment) {
        self.order = order
        self.shop = shop
        let orderID = order.id
        let shopID = shop.id
        _lines = Query(filter: #Predicate<OrderLine> { $0.orderID == orderID })
        _items = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == shopID })
    }

    var body: some View {
        List {
            Section("Articles") {
                ForEach(lines) { line in
                    let title = line.dishName ?? items.first { $0.id == line.catalogItemID }?.title ?? "Article retiré"
                    LabeledContent(title, value: "\(line.quantity) × \(line.unitPriceMinor) \(shop.currencyCode)")
                }
            }
            if order.discountMinor > 0 { LabeledContent("Remise", value: "\(order.discountMinor) \(shop.currencyCode)") }
            LabeledContent("Total", value: "\(order.totalMinor) \(shop.currencyCode)")
            if order.state == .completed && order.totalMinor > 0 {
                NavigationLink {
                    ReceiptDetail(order: order, shop: shop)
                } label: {
                    Label("Voir et partager le reçu", systemImage: "receipt")
                }
            }
        }.navigationTitle("Détail de la commande")
    }
}

