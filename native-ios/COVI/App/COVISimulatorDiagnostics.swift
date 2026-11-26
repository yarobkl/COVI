#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import SwiftData

/// Captures de composants réels, avec des données éphémères entièrement isolées.
/// Ce fichier et ses points d'entrée n'existent ni en Release ni sur un iPhone physique.
@MainActor
final class COVISimulatorDiagnostics {
    static let argument = "--covi-diagnostic-scenario"

    enum Scenario: String {
        case welcome
        case boutiqueHome = "boutique-home"
        case sale = "boutique-sale"
        case checkout = "boutique-checkout"
        case restaurantTables = "restaurant-tables"
        case restaurantTable = "restaurant-table"
        case restaurantOrder = "restaurant-order"
        case salonCatalog = "salon-catalog"
        case salonReport = "salon-report"
        case salonCheckout = "salon-checkout"
        case salonToday = "salon-today"
        case salonAgenda = "salon-agenda"
        case salonBooking = "salon-booking"
        case salonBookingConflict = "salon-booking-conflict"
        case salonClients = "salon-clients"
        case salonProfile = "salon-profile"
    }

    struct RestaurantSample {
        let table: DiningTable
        let order: CommerceOrder
        let lines: [OrderLine]
        let menu: [CatalogItem]
        let draft: [UUID: Int]
        let service: RestaurantService
    }

    struct SalonBookingSample {
        let clientID: UUID
        let serviceID: UUID
        let stylistID: UUID
        let start: Date
    }

    enum Failure: Error { case invalidScenario }

    let scenario: Scenario
    let container: ModelContainer
    let session: AppSession
    let pin: PINManager
    let owner: UUID
    let shop: Establishment
    let basket: [UUID: Int]
    let due: Int64
    let cashReceived: Int64 = 40_000
    private(set) var restaurantSample: RestaurantSample?
    private(set) var salonCatalogItems: [CatalogItem] = []
    private(set) var salonClock: Date?
    private(set) var salonBooking: SalonBookingSample?
    private(set) var salonProfileID: UUID?

    init(arguments: [String]) throws {
        guard let index = arguments.firstIndex(of: Self.argument),
              arguments.indices.contains(index + 1),
              let scenario = Scenario(rawValue: arguments[index + 1]) else {
            throw Failure.invalidScenario
        }
        self.scenario = scenario

        // Même ensemble de modèles que le stockage natif, mais aucune URL disque,
        // aucune réplication CloudKit et aucune restauration de compte réel.
        let schema = Schema([
            MaintenanceEntry.self,
            SalonVisit.self, SalonClient.self, SalonSaleLine.self, SalonStaff.self,
            Bale.self, SyncCheckpoint.self, CloudAccountBinding.self,
            ReceiptCloudCheckpoint.self, ReceiptCloudMarker.self,
            ExpenseCloudCheckpoint.self, ExpenseCloudMarker.self, PendingExpenseVoid.self,
            OperationalCloudCheckpoint.self, OperationalCloudMarker.self,
            Account.self, Establishment.self, Membership.self, ExpenseEntry.self,
            CatalogItem.self, DiningTable.self, CommerceOrder.self,
            Refund.self, OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self
        ])
        let configuration = ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])

        let storage = COVISimulatorMemoryStore()
        session = AppSession(keychain: storage)
        pin = PINManager(keychain: storage)
        owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let kind: BusinessKind
        let name: String
        switch scenario {
        case .restaurantTables, .restaurantTable, .restaurantOrder:
            kind = .restaurant
            name = "Restaurant de démonstration"
        case .salonCatalog, .salonReport, .salonCheckout, .salonToday, .salonAgenda, .salonBooking, .salonBookingConflict, .salonClients, .salonProfile:
            kind = .salon
            name = "Studio Élégance"
        default:
            kind = .boutique
            name = "Boutique de démonstration"
        }
        shop = Establishment(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            ownerID: owner, name: name, kind: kind, city: "Brazzaville", currencyCode: "XAF")

        if kind == .restaurant {
            basket = [:]
            due = 0
            restaurantSample = try seedRestaurantTables()
            return
        }
        if kind == .salon {
            basket = [:]
            due = 0
            if scenario == .salonClients || scenario == .salonProfile {
                try seedSalonDirectory()
            } else if scenario == .salonReport {
                try seedSalonReport()
            } else {
                try seedSalon()
            }
            return
        }

        let shirt = CatalogItem(establishmentID: shop.id,
            title: "Chemise Lin Noir (M)", priceMinor: 18_000)
        shirt.id = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        shirt.stockOnHand = 4
        let trousers = CatalogItem(establishmentID: shop.id,
            title: "Pantalon Chino Beige", priceMinor: 17_000)
        trousers.id = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        trousers.stockOnHand = 7
        let context = container.mainContext
        context.insert(shop)
        context.insert(shirt)
        context.insert(trousers)
        try context.save()

        basket = [shirt.id: 1, trousers.id: 1]
        due = try BoutiqueLedger.total([
            .init(product: shirt, units: 1),
            .init(product: trousers, units: 1)
        ], discount: 0)

        if scenario == .boutiqueHome {
            let whiteShirt = CatalogItem(establishmentID: shop.id,
                title: "Chemise Lin Blanc", priceMinor: 18_500)
            whiteShirt.stockOnHand = 2
            context.insert(whiteShirt)
            try context.save()

            try BoutiqueLedger.sell([
                .init(product: whiteShirt, units: 1)
            ], discount: 0, quote: whiteShirt.priceMinor, tender: .airtel, received: nil,
                confirmed: true, shop: shop, actor: owner, pin: pin, context: context)
            try BoutiqueLedger.sell([
                .init(product: shirt, units: 1),
                .init(product: trousers, units: 1)
            ], discount: 0, quote: due, tender: .cash, received: cashReceived,
                confirmed: false, shop: shop, actor: owner, pin: pin, context: context)
        }
    }

    private func seedRestaurantTables() throws -> RestaurantSample {
        let context = container.mainContext
        let occupied = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
        let free = DiningTable(establishmentID: shop.id, label: "Table 02", capacity: 2)
        let secondOccupied = DiningTable(establishmentID: shop.id, label: "Table 03", capacity: 6)
        let awaitingBill = DiningTable(establishmentID: shop.id, label: "Table 04", capacity: 4)
        for table in [occupied, free, secondOccupied, awaitingBill] {
            context.insert(table)
        }
        context.insert(shop)

        let main = CatalogItem(establishmentID: shop.id, title: "Capitaine à la braise", priceMinor: 9_500)
        let chicken = CatalogItem(establishmentID: shop.id, title: "Poulet braisé entier", priceMinor: 8_000)
        let greens = CatalogItem(establishmentID: shop.id, title: "Saka-Saka et poisson salé", priceMinor: 5_500)
        let liboke = CatalogItem(establishmentID: shop.id, title: "Liboké de silure", priceMinor: 9_000)
        let juice = CatalogItem(establishmentID: shop.id, title: "Jus de bissap frais", priceMinor: 1_500)
        let menu = [chicken, main, greens, liboke, juice]
        for item in menu {
            item.menuCategory = item.id == juice.id ? MenuGroup.drinks.rawValue : MenuGroup.food.rawValue
            context.insert(item)
        }
        liboke.soldOut = true
        try context.save()

        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: pin, db: context)

        func open(_ table: DiningTable) throws -> CommerceOrder {
            try service.open(table)
            guard let id = table.activeSessionID,
                  let order = try context.fetch(FetchDescriptor<CommerceOrder>(
                    predicate: #Predicate { $0.id == id })).first else { throw Failure.invalidScenario }
            return order
        }

        let active = try open(occupied)
        let draft = [chicken.id: 2, main.id: 1]
        for (dish, quantity) in [(chicken, 2), (main, 1), (juice, 2)] {
            try service.send([dish.id: quantity], menu: menu, table: occupied, order: active)
        }
        let activeID = active.id
        let lines = try context.fetch(FetchDescriptor<OrderLine>(
            predicate: #Predicate { $0.orderID == activeID }, sortBy: [SortDescriptor(\.sentAt)]))
        for line in lines where line.catalogItemID != main.id {
            try service.advance(line, from: .cooking, table: occupied, order: active)
            try service.advance(line, from: .ready, table: occupied, order: active)
        }
        let other = try open(secondOccupied)
        try service.send([chicken.id: 8], menu: menu, table: secondOccupied, order: other)
        let bill = try open(awaitingBill)
        try service.send([main.id: 2], menu: menu, table: awaitingBill, order: bill)
        try service.finish(awaitingBill, order: bill, paid: false)

        return RestaurantSample(table: occupied, order: active, lines: lines,
            menu: menu, draft: draft, service: service)
    }

    private func seedSalon() throws {
        let context = container.mainContext
        guard let opening = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) else {
            throw Failure.invalidScenario
        }
        salonClock = opening.addingTimeInterval(25 * 60)
        context.insert(shop)

        let chloe = SalonStaff(shop: shop.id, name: "Chloé")
        let brice = SalonStaff(shop: shop.id, name: "Brice")
        let sarah = SalonStaff(shop: shop.id, name: "Sarah")
        for person in [chloe, brice, sarah] { context.insert(person) }

        let braids = CatalogItem(establishmentID: shop.id, title: "Tresses Box Braids",
            priceMinor: 20_000, isService: true)
        let haircut = CatalogItem(establishmentID: shop.id, title: "Coupe & Barbe VIP",
            priceMinor: 12_000, isService: true)
        let treatment = CatalogItem(establishmentID: shop.id, title: "Soin Kératine",
            priceMinor: 15_000, isService: true)
        for item in [braids, haircut, treatment] { context.insert(item) }

        if scenario == .salonCheckout || scenario == .salonCatalog {
            braids.priceMinor = 25_000
            let serum = CatalogItem(establishmentID: shop.id, title: "Sérum Karité & Argan", priceMinor: 5_000)
            serum.stockOnHand = 5
            context.insert(serum)
            salonCatalogItems = [braids, haircut, treatment, serum]
        }
        let appointments: [(name: String, service: CatalogItem, person: SalonStaff,
            startsAfterOpening: Int, duration: Int, walkIn: Bool)] = [
                ("Yannick M.", haircut, brice, 15, 45, true),
                ("Mireille K.", braids, chloe, 30, 120, false),
                ("Ornella B.", treatment, sarah, 60, 60, false)
            ]
        for appointment in appointments {
            let client = SalonClient(shop: shop.id, name: appointment.name)
            context.insert(client)
            let start = opening.addingTimeInterval(TimeInterval(appointment.startsAfterOpening * 60))
            context.insert(SalonVisit(shop: shop.id, client: client.id, service: appointment.service.id,
                stylist: appointment.person.name, start: start,
                end: start.addingTimeInterval(TimeInterval(appointment.duration * 60)), walkIn: appointment.walkIn))
        }

        let paidClient = SalonClient(shop: shop.id, name: "Grâce T.")
        context.insert(paidClient)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
        order.createdAt = opening
        order.state = .completed
        order.totalMinor = treatment.priceMinor
        context.insert(order)
        context.insert(SalonSaleLine(order: order, client: paidClient.id, stylist: sarah.name,
            item: treatment, units: 1, gross: treatment.priceMinor))
        let paid = SalonVisit(shop: shop.id, client: paidClient.id, service: treatment.id,
            stylist: sarah.name, start: opening, end: opening.addingTimeInterval(20 * 60), walkIn: false)
        paid.receipt = order.id
        context.insert(paid)

        if scenario == .salonBooking || scenario == .salonBookingConflict {
            let calendar = Calendar.current
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: opening),
                  let start = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow) else {
                throw Failure.invalidScenario
            }
            let client = SalonClient(shop: shop.id, name: "Grâce Tchicaya")
            client.phone = "+242 06 410 22 15"
            let service = CatalogItem(establishmentID: shop.id, title: "Tresses Knotless Moyennes",
                priceMinor: 25_000, isService: true)
            context.insert(client)
            context.insert(service)
            if scenario == .salonBookingConflict {
                context.insert(SalonVisit(shop: shop.id, client: paidClient.id, service: treatment.id,
                    stylist: sarah.name, start: start, end: start.addingTimeInterval(3_600), walkIn: false))
            }
            salonBooking = SalonBookingSample(clientID: client.id, serviceID: service.id,
                stylistID: sarah.id, start: start)
        }
        try context.save()
    }

    private func seedSalonDirectory() throws {
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date.now
        context.insert(shop)

        let mireille = SalonClient(shop: shop.id, name: "Mireille K.")
        mireille.phone = "+242 00 000 00 01"
        mireille.preferences = "Coiffeuse préférée : Chloé."
        mireille.notes = "Cuir chevelu sensible. Préfère les mèches longues."
        let yannick = SalonClient(shop: shop.id, name: "Yannick M.")
        yannick.phone = "+242 00 000 00 02"
        let grace = SalonClient(shop: shop.id, name: "Grâce T.")
        let cedric = SalonClient(shop: shop.id, name: "Cédric L.")
        for client in [mireille, yannick, grace, cedric] { context.insert(client) }

        let chloe = SalonStaff(shop: shop.id, name: "Chloé")
        context.insert(chloe)
        let braids = CatalogItem(establishmentID: shop.id, title: "Tresses Box Braids",
            priceMinor: 25_000, isService: true)
        let treatment = CatalogItem(establishmentID: shop.id, title: "Soin Kératine",
            priceMinor: 20_000, isService: true)
        let knotless = CatalogItem(establishmentID: shop.id, title: "Tresses Knotless",
            priceMinor: 25_000, isService: true)
        for service in [braids, treatment, knotless] { context.insert(service) }

        for (service, daysAgo) in [(braids, 2), (treatment, 21), (knotless, 42)] {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
                throw Failure.invalidScenario
            }
            let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
            order.customerID = mireille.id
            order.createdAt = date
            order.totalMinor = service.priceMinor
            order.state = .completed
            context.insert(order)
            context.insert(SalonSaleLine(order: order, client: mireille.id, stylist: chloe.name,
                item: service, units: 1, gross: service.priceMinor))
        }

        let start = now.addingTimeInterval(24 * 3_600)
        context.insert(SalonVisit(shop: shop.id, client: grace.id, service: knotless.id,
            stylist: chloe.name, start: start, end: start.addingTimeInterval(7_200), walkIn: false))
        if scenario == .salonProfile { salonProfileID = mireille.id }
        try context.save()
    }

    private func seedSalonReport() throws {
        let context = container.mainContext
        context.insert(shop)
        let client = SalonClient(shop: shop.id, name: "Cliente de démonstration")
        context.insert(client)
        let receipts: [(stylist: String, label: String, amount: Int64, service: Bool, rate: Int)] = [
            ("Chloé M.", "Tresses Box Braids", 105_000, true, 40),
            ("Brice K.", "Coupe et barbe", 51_000, true, 40),
            ("Sarah M.", "Soin Kératine", 68_000, true, 40),
            ("Brice K.", "Produits de soin", 44_000, false, 0)
        ]
        let start = Date.now
        for receipt in receipts {
            let item = CatalogItem(establishmentID: shop.id, title: receipt.label,
                priceMinor: receipt.amount, isService: receipt.service)
            item.salonPercent = receipt.rate
            context.insert(item)
            let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
            order.createdAt = start
            order.customerID = client.id
            order.totalMinor = receipt.amount
            order.state = .completed
            context.insert(order)
            context.insert(SalonSaleLine(order: order, client: client.id, stylist: receipt.stylist,
                item: item, units: 1, gross: receipt.amount))
            if receipt.service {
                let visit = SalonVisit(shop: shop.id, client: client.id, service: item.id,
                    stylist: receipt.stylist, start: start, end: start.addingTimeInterval(3_600), walkIn: false)
                visit.receipt = order.id
                context.insert(visit)
            }
        }
        try context.save()
    }

    /// Le workflow attend ce signal avant la capture ; aucun détail métier n'y figure.
    func signalAfterPresentation() async {
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try signalReady()
        } catch {
            // Une présentation annulée ou un signal impossible font échouer le diagnostic.
        }
    }

    private func signalReady() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("covi-diagnostic-\(scenario.rawValue).ready")
        try Data(scenario.rawValue.utf8).write(to: marker, options: .atomic)
    }
}

final class COVISimulatorMemoryStore: SecureStorage {
    private var values: [String: Data] = [:]
    func save(_ data: Data, for key: String) throws { values[key] = data }
    func data(for key: String) throws -> Data? { values[key] }
    func delete(_ key: String) throws { values.removeValue(forKey: key) }
}

private struct COVISimulatorDiagnosticsKey: EnvironmentKey {
    static let defaultValue: COVISimulatorDiagnostics? = nil
}

extension EnvironmentValues {
    var coviSimulatorDiagnostics: COVISimulatorDiagnostics? {
        get { self[COVISimulatorDiagnosticsKey.self] }
        set { self[COVISimulatorDiagnosticsKey.self] = newValue }
    }
}

@MainActor
struct COVISimulatorDiagnosticView: View {
    let fixture: COVISimulatorDiagnostics

    var body: some View {
        Group {
            if fixture.scenario == .welcome {
                // La session mémoire est vide : RootView affiche le véritable accueil
                // sans compte restauré et sans démarrer une synchronisation.
                RootView()
            } else if fixture.scenario == .salonCatalog {
                NavigationStack {
                    SalonCatalog(shop: fixture.shop, menu: fixture.salonCatalogItems, actor: fixture.owner)
                }
            } else if let sample = fixture.restaurantSample, fixture.scenario == .restaurantTable {
                NavigationStack {
                    RestaurantTable(table: sample.table, order: sample.order, menu: sample.menu,
                        lines: sample.lines, service: sample.service)
                }
            } else if let sample = fixture.restaurantSample, fixture.scenario == .restaurantOrder {
                RestaurantComposer(menu: sample.menu, table: sample.table, order: sample.order,
                    service: sample.service)
            } else {
                // Navigation et onglets réels, avec les contrôles de rôle/PIN normaux.
                // Le header RootView/ShopSyncStatus est volontairement hors capture :
                // sa création démarrerait la synchronisation du propriétaire.
                DynamicTabView(establishment: fixture.shop, accountID: fixture.owner,
                    role: .owner, pinManager: fixture.pin, onSwitchShop: {})
            }
        }
        .environment(\.coviSimulatorDiagnostics, fixture)
        .allowsHitTesting(false)
        .task {
            // Le formulaire et la fiche Salon signalent leur propre apparition.
            if fixture.salonBooking == nil && fixture.salonProfileID == nil && fixture.scenario != .salonReport {
                await fixture.signalAfterPresentation()
            }
        }
    }
}
#endif

