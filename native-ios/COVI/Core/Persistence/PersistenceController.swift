import SwiftData

enum PersistenceController {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MaintenanceEntry.self,
            SalonVisit.self, SalonClient.self, SalonSaleLine.self,
            Bale.self, SyncCheckpoint.self, Account.self, Establishment.self, Membership.self,
            CatalogItem.self, DiningTable.self, CommerceOrder.self,
            Refund.self, OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self
        ])
        // Local-first. CloudKit est volontairement NON activé ici :
        // les modèles, migrations et droits de partage doivent être audités avant activation.
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        ])
    }
}
