import SwiftData

enum PersistenceController {
    static func makeContainer() throws -> ModelContainer {
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
        // SwiftData reste local-first. La réplication iCloud passe par les
        // journaux et miroirs CloudKit explicites, vérifiés et isolés par boutique.
        // Ne pas activer la réplication SwiftData automatique en parallèle :
        // elle court-circuiterait la validation des reçus et conflits de stock.
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        ])
    }
}
