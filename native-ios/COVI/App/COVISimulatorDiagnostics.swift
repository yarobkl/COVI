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
        shop = Establishment(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            ownerID: owner, name: "Boutique de démonstration", kind: .boutique,
            city: "Brazzaville", currencyCode: "XAF")

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

    /// Le workflow attend ce signal avant la capture ; aucun détail métier n'y figure.
    func signalReady() throws {
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
            do {
                // Laisse se terminer les tâches d'état et la présentation native de sheet.
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try fixture.signalReady()
            } catch {
                // Pas de signal en cas d'annulation/échec : le workflow échoue fermé.
            }
        }
    }
}
#endif

