import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CloudOperationalSyncTests: XCTestCase {
    private func memory() throws -> ModelContext {
        let schema = Schema([
            Establishment.self, CatalogItem.self, Bale.self, StockMovement.self,
            SalonClient.self, SalonStaff.self, SalonVisit.self, SalonSaleLine.self,
            DiningTable.self, CommerceOrder.self, OrderLine.self, PaymentRecord.self,
            Membership.self, OperationalCloudMarker.self, OperationalCloudCheckpoint.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        return ModelContext(container)
    }

    private func clone(_ shop: Establishment) -> Establishment {
        Establishment(id: shop.id, ownerID: shop.ownerID, name: shop.name,
            kind: shop.kind, city: shop.city, currencyCode: shop.currencyCode)
    }

    private func export(_ db: ModelContext, shop: Establishment) throws -> [(String, Data)] {
        try CloudOperationalSync.capture(shop: shop, context: db).map { ($0.key, try $0.bytes()) }
    }

    func testInventoryAndBalesSyncOnceWithoutDuplicatingMovements() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        let copy = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_500)
        item.stockOnHand = 3
        let bale = Bale(shop: shop.id, label: "Lot de riz", cost: 15_000)
        let received = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: 5, reason: "Arrivage", actorID: owner)
        received.baleID = bale.id
        let sold = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -2, reason: "Vente validée", actorID: owner)
        source.insert(shop); source.insert(item); source.insert(bale)
        source.insert(received); source.insert(sold); try source.save()
        target.insert(copy); try target.save()

        let batch = try export(source, shop: shop)
        try CloudOperationalSync.merge(Array(batch.reversed()), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try CloudOperationalSync.validateStock(shop: copy, context: target)
        try target.save()
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<CatalogItem>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<StockMovement>()), 2)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Bale>()), 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CatalogItem>()).first?.stockOnHand, 3)

        try CloudOperationalSync.merge(batch, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<StockMovement>()), 2)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CatalogItem>()).first?.stockOnHand, 3)
    }

    func testClientStaffAndBookingImportWithStableIdentifiers() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Pointe-Noire")
        let copy = clone(shop)
        let client = SalonClient(shop: shop.id, name: "Cliente")
        client.phone = "+242 06 000 00 00"
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeuse")
        let service = CatalogItem(establishmentID: shop.id, title: "Tresses",
            priceMinor: 5_000, isService: true)
        let appointment = SalonVisit(shop: shop.id, client: client.id, service: service.id,
            stylist: stylist.name, start: Date.now.addingTimeInterval(3_600),
            end: Date.now.addingTimeInterval(5_400), walkIn: false)
        source.insert(shop); source.insert(client); source.insert(stylist)
        source.insert(service); source.insert(appointment); try source.save()
        target.insert(copy); try target.save()

        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertEqual(try target.fetch(FetchDescriptor<SalonClient>()).first?.id, client.id)
        XCTAssertEqual(try target.fetch(FetchDescriptor<SalonClient>()).first?.phone, client.phone)
        XCTAssertEqual(try target.fetch(FetchDescriptor<SalonStaff>()).first?.id, stylist.id)
        XCTAssertEqual(try target.fetch(FetchDescriptor<SalonVisit>()).first?.id, appointment.id)
        XCTAssertEqual(try target.fetch(FetchDescriptor<SalonVisit>()).first?.service, service.id)
    }

    func testRemoteCatalogEditUpdatesUnmodifiedDeviceButNotDivergedLocalEdits() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Libreville")
        let copy = clone(shop)
        let product = CatalogItem(establishmentID: shop.id, title: "Sucre", priceMinor: 1_000)
        source.insert(shop); source.insert(product); try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()

        product.priceMinor = 1_200
        try source.save()
        let updated = try export(source, shop: shop)
        try CloudOperationalSync.merge(updated, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let imported = try XCTUnwrap(target.fetch(FetchDescriptor<CatalogItem>()).first)
        XCTAssertEqual(imported.priceMinor, 1_200)

        imported.priceMinor = 1_300
        product.priceMinor = 1_400
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(source, shop: shop),
            shop: copy, cloudUserID: "iCloud-A", context: target))
        XCTAssertEqual(imported.priceMinor, 1_300)
    }

    func testUnchangedRemoteDoesNotOverrideOfflineLocalCatalogEdit() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Douala")
        let copy = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Huile", priceMinor: 2_500)
        source.insert(shop); source.insert(item); try source.save()
        target.insert(copy); try target.save()
        let baseline = try export(source, shop: shop)
        try CloudOperationalSync.merge(baseline, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let local = try XCTUnwrap(target.fetch(FetchDescriptor<CatalogItem>()).first)
        local.priceMinor = 2_800
        try CloudOperationalSync.merge(baseline, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        XCTAssertEqual(local.priceMinor, 2_800)
        XCTAssertNotEqual(try export(target, shop: copy).first?.1, baseline.first?.1)
    }

    func testOperationalCloudRejectsAnotherShopAndAnotherICloudAccount() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let client = SalonClient(shop: shop.id, name: "Cliente")
        source.insert(shop); source.insert(client); try source.save()
        let copy = clone(shop)
        target.insert(copy); try target.save()
        let batch = try export(source, shop: shop)
        let foreign = Establishment(ownerID: UUID(), name: "Autre", kind: .salon, city: "Douala")
        XCTAssertThrowsError(try CloudOperationalSync.merge(batch, shop: foreign,
            cloudUserID: "iCloud-A", context: target))
        try CloudOperationalSync.merge(batch, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertThrowsError(try CloudOperationalSync.merge(batch, shop: copy,
            cloudUserID: "iCloud-B", context: target))
    }

    func testInventoryValidationRefusesUntrackedOrOversoldStock() throws {
        let db = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Douala")
        let product = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_500)
        product.stockOnHand = 9
        db.insert(shop); db.insert(product); try db.save()
        XCTAssertThrowsError(try CloudOperationalSync.validateStock(shop: shop, context: db))
        let movement = StockMovement(establishmentID: shop.id, itemID: product.id,
            delta: 9, reason: "Inventaire initial", actorID: owner)
        db.insert(movement); try db.save()
        XCTAssertNoThrow(try CloudOperationalSync.validateStock(shop: shop, context: db))
        product.stockOnHand = 8
        XCTAssertThrowsError(try CloudOperationalSync.validateStock(shop: shop, context: db))
    }

    func testRestaurantOpenSessionThenVerifiedReceiptCompletesWithoutDuplicatePayments() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let copy = clone(shop)
        let dish = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 4_000)
        dish.menuCategory = MenuGroup.food.rawValue
        let table = DiningTable(establishmentID: shop.id, label: "T1", capacity: 4)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner, tableID: table.id)
        order.state = .accepted
        order.totalMinor = 4_000
        table.isOccupied = true; table.activeSessionID = order.id
        let line = OrderLine(orderID: order.id, catalogItemID: dish.id,
            quantity: 1, unitPriceMinor: 4_000)
        line.dishName = "Poulet"; line.preparation = Prep.cooking.rawValue
        source.insert(shop); source.insert(dish); source.insert(table)
        source.insert(order); source.insert(line); try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop),
            shop: copy, cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.state, .accepted)
        XCTAssertEqual(try target.fetch(FetchDescriptor<DiningTable>()).first?.isOccupied, true)

        order.state = .completed; table.isOccupied = false; table.activeSessionID = nil
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.cash.rawValue, amountMinor: 4_000, confirmedByID: owner)
        source.insert(payment); try source.save()
        let receipt = try ArchivedReceipt(shop: shop, order: order,
            lines: [line], payments: [payment], catalog: [dish])
        try receipt.importIfNeeded(shop: copy, context: target)
        try target.save()
        try receipt.importIfNeeded(shop: copy, context: target)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.state, .completed)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<DiningTable>()).first?.isOccupied, false)
    }
}
