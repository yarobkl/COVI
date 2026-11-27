import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CloudOperationalSyncTests: XCTestCase {
    func testProductionSchemaNamesMatchPreparedCloudKitDevelopmentTypes() {
        XCTAssertEqual(CloudKitSchemaContract.container, "iCloud.com.covi.app")
        XCTAssertEqual(CloudKitSchemaContract.recordTypes,
            ["COVIAccountIndex", "COVIEvent", "COVIOperationalState"])
        XCTAssertEqual(CloudKitSchemaContract.payloadField, "payload")
    }

    private func memory() throws -> ModelContext {
        let schema = Schema([
            Establishment.self, CatalogItem.self, Bale.self, StockMovement.self,
            SalonClient.self, SalonStaff.self, SalonVisit.self, SalonSaleLine.self,
            DiningTable.self, CommerceOrder.self, OrderLine.self, PaymentRecord.self,
            Membership.self, OperationalCloudMarker.self, OperationalCloudCheckpoint.self,
            OutboxEvent.self
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

    func testUnknownAndZeroBaleCostsRemainDistinctAfterRepeatedSync() throws {
        let source = try memory()
        let target = try memory()
        let shop = Establishment(ownerID: UUID(), name: "Boutique", kind: .boutique, city: "Brazzaville")
        let copy = clone(shop)
        source.insert(shop)
        source.insert(Bale(shop: shop.id, label: "Inconnu", cost: nil))
        source.insert(Bale(shop: shop.id, label: "Gratuit", cost: 0))
        source.insert(Bale(shop: shop.id, label: "Achat", cost: 12500))
        try source.save()
        target.insert(copy)
        try target.save()
        let batch = try export(source, shop: shop)
        for _ in 0..<2 {
            try CloudOperationalSync.merge(batch, shop: copy, cloudUserID: "iCloud-A", context: target)
            try target.save()
        }
        let reopened = ModelContext(target.container)
        let lots = try reopened.fetch(FetchDescriptor<Bale>())
        XCTAssertEqual(lots.count, 3)
        let unknown = try XCTUnwrap(lots.first { $0.label == "Inconnu" })
        let free = try XCTUnwrap(lots.first { $0.label == "Gratuit" })
        let paid = try XCTUnwrap(lots.first { $0.label == "Achat" })
        XCTAssertNil(unknown.knownCost)
        XCTAssertEqual(free.knownCost, 0)
        XCTAssertEqual(paid.knownCost, 12500)
    }

    func testCatalogDurationSurvivesLegacyUpdatesAndCanBeClearedByNewSnapshots() throws {
        let source = try memory(), target = try memory()
        let shop = Establishment(ownerID: UUID(), name: "Salon", kind: .salon, city: "Brazzaville")
        let copy = clone(shop)
        let service = CatalogItem(establishmentID: shop.id, title: "Tresses", priceMinor: 5_000, isService: true)
        source.insert(shop); source.insert(service); try source.save()
        target.insert(copy); try target.save()

        let initial = try XCTUnwrap(CloudOperationalSync.capture(shop: shop, context: source).first)
        XCTAssertNil(try JSONDecoder().decode(OperationalCatalog.self, from: initial.state).durationIsTracked)
        try CloudOperationalSync.merge([(initial.key, try initial.bytes())], shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        service.salonDurationMinutes = 150
        let expected = try XCTUnwrap(CloudOperationalSync.capture(shop: shop, context: source).first)
        try CloudOperationalSync.merge([(expected.key, try expected.bytes())], shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let item = try XCTUnwrap(target.fetch(FetchDescriptor<CatalogItem>()).first)
        XCTAssertEqual(item.salonDurationMinutes, 150)

        service.salonDurationMinutes = nil
        service.salonDurationWasCleared = true
        let cleared = try XCTUnwrap(CloudOperationalSync.capture(shop: shop, context: source).first)
        try CloudOperationalSync.merge([(cleared.key, try cleared.bytes())], shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertNil(item.salonDurationMinutes)
        XCTAssertEqual(item.salonDurationWasCleared, true)
        try CloudOperationalSync.merge([(expected.key, try expected.bytes())], shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()

        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: expected.state) as? [String: Any])
        state.removeValue(forKey: "durationMinutes")
        state.removeValue(forKey: "durationIsTracked")
        state["price"] = 6_000
        let legacy = OperationalCloudRow(version: expected.version, ownerID: expected.ownerID,
            shopID: expected.shopID, kind: .catalog, entityID: expected.entityID,
            state: try JSONSerialization.data(withJSONObject: state))
        try CloudOperationalSync.merge([(legacy.key, try legacy.bytes())], shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertEqual(item.priceMinor, 6_000)
        XCTAssertEqual(item.salonDurationMinutes, 150)

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

    func testRestaurantDrinkReservationAndServiceMovementSurviveRepeatedSync() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let copy = clone(shop)
        let table = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
        let drink = CatalogItem(establishmentID: shop.id, title: "Eau", priceMinor: 1_000)
        drink.menuCategory = MenuGroup.drinks.rawValue
        source.insert(shop); source.insert(table); source.insert(drink); try source.save()
        target.insert(copy); try target.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
            pin: PINManager(keychain: InMemorySecureStore()), db: source)
        try service.adjustDrinkStock(drink, operation: .restock, quantity: 4)
        try service.open(table)
        let order = try XCTUnwrap(source.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.send([drink.id: 2], menu: [drink], table: table, order: order)

        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let mirror = try XCTUnwrap(target.fetch(FetchDescriptor<CatalogItem>()).first)
        XCTAssertEqual(mirror.stockReserved, 2)
        XCTAssertEqual(mirror.stockOnHand, 4)
        XCTAssertEqual(try target.fetch(FetchDescriptor<OrderLine>()).first?.restaurantUsesDrinkStock, true)

        let line = try XCTUnwrap(source.fetch(FetchDescriptor<OrderLine>()).first)
        for phase in [Prep.received, .cooking, .ready] {
            try service.advance(line, from: phase, table: table, order: order)
        }
        let batch = try export(source, shop: shop)
        for _ in 0..<2 {
            try CloudOperationalSync.merge(batch, shop: copy, cloudUserID: "iCloud-A", context: target)
            try CloudOperationalSync.validateStock(shop: copy, context: target)
            try target.save()
        }
        XCTAssertEqual(mirror.stockReserved, 0)
        XCTAssertEqual(mirror.stockOnHand, 2)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<StockMovement>()), 2)
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

    func testSalonCancellationReplicatesWithoutDeletingBookingHistory() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let copy = clone(shop)
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeur")
        let service = CatalogItem(establishmentID: shop.id, title: "Coupe", priceMinor: 3_000,
                                  isService: true)
        let start = Date.now.addingTimeInterval(7_200)
        let visit = SalonVisit(shop: shop.id, client: client.id, service: service.id,
            stylist: stylist.name, start: start, end: start.addingTimeInterval(1_800), walkIn: false)
        source.insert(shop); source.insert(client); source.insert(stylist)
        source.insert(service); source.insert(visit); try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()

        visit.cancelled = true; try source.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let copied = try XCTUnwrap(target.fetch(FetchDescriptor<SalonVisit>()).first)
        XCTAssertEqual(copied.id, visit.id)
        XCTAssertTrue(copied.cancelled)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<SalonVisit>()), 1)
    }

    func testTwoDevicesCannotSilentlyDoubleBookSameStylist() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Pointe-Noire")
        let copy = clone(shop)
        let first = SalonClient(shop: shop.id, name: "Cliente A")
        let second = SalonClient(shop: shop.id, name: "Cliente B")
        let service = CatalogItem(establishmentID: shop.id, title: "Coupe",
            priceMinor: 4_000, isService: true)
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeur")
        let start = Date.now.addingTimeInterval(7_200)
        let firstVisit = SalonVisit(shop: shop.id, client: first.id, service: service.id,
            stylist: stylist.name, start: start, end: start.addingTimeInterval(3_600), walkIn: false)
        source.insert(shop); source.insert(first); source.insert(second)
        source.insert(service); source.insert(stylist); source.insert(firstVisit)
        try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()

        let competing = SalonVisit(shop: shop.id, client: second.id, service: service.id,
            stylist: stylist.name, start: start.addingTimeInterval(300),
            end: start.addingTimeInterval(1_800), walkIn: false)
        source.insert(competing); try source.save()
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(source, shop: shop),
            shop: copy, cloudUserID: "iCloud-A", context: target))
        target.rollback()
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<SalonVisit>()), 1)
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

    func testCloudStockRejectsConcurrentOversellingInsteadOfGoingNegative() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        let copy = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_500)
        item.stockOnHand = 1
        let incoming = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: 1, reason: "Inventaire", actorID: owner)
        source.insert(shop); source.insert(item); source.insert(incoming); try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let sale = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -2, reason: "Vente concurrente", actorID: owner)
        source.insert(sale); try source.save()
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(source, shop: shop),
            shop: copy, cloudUserID: "iCloud-A", context: target))
        target.rollback()
        XCTAssertEqual(try target.fetch(FetchDescriptor<CatalogItem>()).first?.stockOnHand, 1)
    }

    func testStockHistoryIsImmutableAfterFirstCloudImport() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        let copy = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Farine", priceMinor: 2_000)
        item.stockOnHand = 5
        let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: 5, reason: "Arrivage", actorID: owner)
        source.insert(shop); source.insert(item); source.insert(movement); try source.save()
        target.insert(copy); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        movement.reason = "Historique réécrit"
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(source, shop: shop),
            shop: copy, cloudUserID: "iCloud-A", context: target))
        XCTAssertEqual(try target.fetch(FetchDescriptor<StockMovement>()).first?.reason, "Arrivage")
    }

    func testKitchenQueueMirrorsReceivedAndClaimedWithoutChangingTheLegacyStatus() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let copy = clone(shop)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner)
        order.state = .accepted
        let line = OrderLine(orderID: order.id, catalogItemID: UUID(), quantity: 1, unitPriceMinor: 5_000)
        line.preparation = Prep.received.rawValue
        source.insert(shop); source.insert(order); source.insert(line)
        target.insert(copy)
        try source.save(); try target.save()
        let pending = try JSONDecoder().decode(OperationalKitchenLine.self,
            from: JSONEncoder().encode(OperationalKitchenLine(line)))
        XCTAssertEqual(pending.preparation, Prep.cooking.rawValue)
        XCTAssertEqual(pending.awaitingClaim, true)
        let pendingRows = try export(source, shop: shop)
        try CloudOperationalSync.merge(pendingRows, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let mirrored = try XCTUnwrap(target.fetch(FetchDescriptor<OrderLine>()).first)
        XCTAssertEqual(mirrored.preparation, Prep.received.rawValue)

        line.preparation = Prep.cooking.rawValue
        try source.save()
        XCTAssertNil(OperationalKitchenLine(line).awaitingClaim)
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertEqual(mirrored.preparation, Prep.cooking.rawValue)
        try CloudOperationalSync.merge(pendingRows, shop: copy, cloudUserID: "iCloud-A", context: target)
        XCTAssertEqual(mirrored.preparation, Prep.cooking.rawValue)
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
        order.restaurantGuestCount = 3
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
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.restaurantGuestCount, 3)
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
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.restaurantGuestCount, 3)
        XCTAssertEqual(try JSONDecoder().decode(ArchivedReceipt.self, from: JSONEncoder().encode(receipt)).guestCount, 3)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<DiningTable>()).first?.isOccupied, false)
    }

    func testVerifiedRestaurantReceiptPreservesMatchingPartialPaymentsAndRefusesCompetingReceipt() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let copy = clone(shop)
        let table = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner, tableID: table.id)
        order.state = .accepted
        order.totalMinor = 4_000
        table.activeSessionID = order.id
        table.isOccupied = true
        table.billRequested = true
        let line = OrderLine(orderID: order.id, catalogItemID: UUID(), quantity: 1, unitPriceMinor: 4_000)
        line.dishName = "Poulet"
        line.preparation = Prep.served.rawValue
        source.insert(shop); source.insert(table); source.insert(order); source.insert(line)
        target.insert(copy)
        try source.save(); try target.save()
        try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()

        let partial = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.cash.rawValue, amountMinor: 1_500, confirmedByID: owner)
        partial.cashReceived = 1_500
        target.insert(partial)
        try target.save()

        order.totalMinor = 4_500
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(source, shop: shop), shop: copy,
            cloudUserID: "iCloud-A", context: target))
        target.rollback()
        order.totalMinor = 4_000
        order.state = .completed
        let competing = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.cash.rawValue, amountMinor: 4_000, confirmedByID: owner)
        let otherReceipt = try ArchivedReceipt(shop: shop, order: order,
            lines: [line], payments: [competing], catalog: [])
        XCTAssertThrowsError(try otherReceipt.importIfNeeded(shop: copy, context: target))
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 1)

        let finalPayment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.mtn.rawValue, amountMinor: 2_500, confirmedByID: owner)
        let matching = try ArchivedReceipt(shop: shop, order: order,
            lines: [line], payments: [partial, finalPayment], catalog: [])
        try matching.importIfNeeded(shop: copy, context: target)
        try target.save()
        try matching.importIfNeeded(shop: copy, context: target)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.state, .completed)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 2)
        XCTAssertEqual(try target.fetch(FetchDescriptor<DiningTable>()).first?.isOccupied, false)
    }

    func testRestaurantReceiptRetainsOccupancyUntilExplicitReleaseAndRejectsStaleTable() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let copy = clone(shop)
        let table = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner, tableID: table.id)
        order.state = .accepted
        order.totalMinor = 3_000
        table.activeSessionID = order.id
        table.isOccupied = true
        table.billRequested = true
        let line = OrderLine(orderID: order.id, catalogItemID: UUID(), quantity: 1, unitPriceMinor: 3_000)
        line.dishName = "Poisson"
        line.preparation = Prep.served.rawValue
        source.insert(shop); source.insert(table); source.insert(order); source.insert(line)
        target.insert(copy)
        try source.save(); try target.save()
        let initial = try export(source, shop: shop)
        try CloudOperationalSync.merge(initial, shop: copy, cloudUserID: "iCloud-A", context: target)
        try target.save()
        let mirrored = try XCTUnwrap(target.fetch(FetchDescriptor<DiningTable>()).first)

        order.state = .completed
        order.restaurantKeepsTable = true
        table.billRequested = false
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.cash.rawValue, amountMinor: 3_000, confirmedByID: owner)
        source.insert(payment)
        try source.save()
        let paidRoom = try export(source, shop: shop)
        let receipt = try ArchivedReceipt(shop: shop, order: order, lines: [line], payments: [payment], catalog: [])
        try receipt.importIfNeeded(shop: copy, context: target)
        try target.save()
        XCTAssertTrue(mirrored.isOccupied)
        XCTAssertFalse(mirrored.billRequested)
        try CloudOperationalSync.merge(paidRoom, shop: copy, cloudUserID: "iCloud-A", context: target)
        try target.save()

        table.activeSessionID = nil
        table.isOccupied = false
        table.lastReleasedSessionID = order.id
        try source.save()
        let releasedRoom = try export(source, shop: shop)
        try CloudOperationalSync.merge(releasedRoom, shop: copy, cloudUserID: "iCloud-A", context: target)
        try target.save()
        XCTAssertFalse(mirrored.isOccupied)
        XCTAssertEqual(mirrored.lastReleasedSessionID, order.id)
        try CloudOperationalSync.merge(paidRoom, shop: copy, cloudUserID: "iCloud-A", context: target)
        try receipt.importIfNeeded(shop: copy, context: target)
        XCTAssertFalse(mirrored.isOccupied)
        XCTAssertNil(mirrored.activeSessionID)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
    }

    func testStaleDiningTableSnapshotCannotReopenPaidSession() throws {
        let source = try memory(), target = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Libreville")
        let copy = clone(shop)
        let dish = CatalogItem(establishmentID: shop.id, title: "Poisson", priceMinor: 3_000)
        dish.menuCategory = MenuGroup.food.rawValue
        let table = DiningTable(establishmentID: shop.id, label: "Terrasse", capacity: 2)
        let order = CommerceOrder(establishmentID: shop.id, createdByID: owner, tableID: table.id)
        order.state = .accepted; order.totalMinor = 3_000
        table.activeSessionID = order.id; table.isOccupied = true
        let line = OrderLine(orderID: order.id, catalogItemID: dish.id,
            quantity: 1, unitPriceMinor: 3_000)
        line.dishName = dish.title
        source.insert(shop); source.insert(dish); source.insert(table)
        source.insert(order); source.insert(line); try source.save()
        let staleRoom = try export(source, shop: shop)

        order.state = .completed
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id,
            method: Tender.cash.rawValue, amountMinor: 3_000, confirmedByID: owner)
        source.insert(payment); try source.save()
        let receipt = try ArchivedReceipt(shop: shop, order: order,
            lines: [line], payments: [payment], catalog: [dish])
        target.insert(copy); try target.save()
        try receipt.importIfNeeded(shop: copy, context: target)
        try CloudOperationalSync.merge(staleRoom, shop: copy,
            cloudUserID: "iCloud-A", context: target)
        try target.save()
        let syncedTable = try XCTUnwrap(target.fetch(FetchDescriptor<DiningTable>()).first)
        XCTAssertEqual(syncedTable.id, table.id)
        XCTAssertFalse(syncedTable.isOccupied)
        XCTAssertNil(syncedTable.activeSessionID)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CommerceOrder>()).first?.state, .completed)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
    }

    func testTwoOfflinePhonesSellSeparateUnitsAndConvergeWithoutDoubleCounting() throws {
        let first = try memory(), second = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Brazzaville")
        let other = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Pain", priceMinor: 500)
        item.stockOnHand = 2
        let arrival = StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: 2, reason: "Arrivage", actorID: owner)
        first.insert(shop); first.insert(item); first.insert(arrival); try first.save()
        second.insert(other); try second.save()
        let baseline = try export(first, shop: shop)
        try CloudOperationalSync.merge(baseline, shop: shop, cloudUserID: "same-iCloud", context: first)
        try CloudOperationalSync.merge(baseline, shop: other, cloudUserID: "same-iCloud", context: second)
        try first.save(); try second.save()

        item.stockOnHand -= 1
        first.insert(StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -1, reason: "Vente appareil 1", actorID: owner))
        let secondItem = try XCTUnwrap(second.fetch(FetchDescriptor<CatalogItem>()).first)
        secondItem.stockOnHand -= 1
        second.insert(StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -1, reason: "Vente appareil 2", actorID: owner))
        try first.save(); try second.save()

        try CloudOperationalSync.merge(try export(first, shop: shop), shop: other,
            cloudUserID: "same-iCloud", context: second)
        try CloudOperationalSync.validateStock(shop: other, context: second)
        try second.save()
        try CloudOperationalSync.merge(try export(second, shop: other), shop: shop,
            cloudUserID: "same-iCloud", context: first)
        try CloudOperationalSync.validateStock(shop: shop, context: first)
        try first.save()
        XCTAssertEqual(item.stockOnHand, 0)
        XCTAssertEqual(secondItem.stockOnHand, 0)
        XCTAssertEqual(try first.fetchCount(FetchDescriptor<StockMovement>()), 3)
        XCTAssertEqual(try second.fetchCount(FetchDescriptor<StockMovement>()), 3)
    }

    func testTwoOfflinePhonesCannotBothSellTheLastUnit() throws {
        let first = try memory(), second = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Douala")
        let other = clone(shop)
        let item = CatalogItem(establishmentID: shop.id, title: "Savon", priceMinor: 800)
        item.stockOnHand = 1
        first.insert(shop); first.insert(item)
        first.insert(StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: 1, reason: "Stock initial", actorID: owner))
        second.insert(other); try first.save(); try second.save()
        let baseline = try export(first, shop: shop)
        try CloudOperationalSync.merge(baseline, shop: shop, cloudUserID: "same-iCloud", context: first)
        try CloudOperationalSync.merge(baseline, shop: other, cloudUserID: "same-iCloud", context: second)
        try first.save(); try second.save()
        let localItem = try XCTUnwrap(second.fetch(FetchDescriptor<CatalogItem>()).first)

        item.stockOnHand = 0; localItem.stockOnHand = 0
        first.insert(StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -1, reason: "Vente A", actorID: owner))
        second.insert(StockMovement(establishmentID: shop.id, itemID: item.id,
            delta: -1, reason: "Vente B", actorID: owner))
        try first.save(); try second.save()
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(first, shop: shop),
            shop: other, cloudUserID: "same-iCloud", context: second))
        second.rollback()
        XCTAssertEqual(localItem.stockOnHand, 0)
        XCTAssertEqual(try second.fetchCount(FetchDescriptor<StockMovement>()), 2)
    }

    func testTwoOfflinePhonesWithIndependentSalonBookingsRefuseOverlappingTime() throws {
        let first = try memory(), second = try memory(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Pointe-Noire")
        let other = clone(shop)
        let a = SalonClient(shop: shop.id, name: "Cliente A")
        let b = SalonClient(shop: shop.id, name: "Cliente B")
        let service = CatalogItem(establishmentID: shop.id, title: "Coupe", priceMinor: 2_000,
            isService: true)
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeur")
        first.insert(shop); first.insert(a); first.insert(b)
        first.insert(service); first.insert(stylist); try first.save()
        second.insert(other); try second.save()
        let baseline = try export(first, shop: shop)
        try CloudOperationalSync.merge(baseline, shop: shop, cloudUserID: "same-iCloud", context: first)
        try CloudOperationalSync.merge(baseline, shop: other, cloudUserID: "same-iCloud", context: second)
        try first.save(); try second.save()

        let start = Date.now.addingTimeInterval(4_000)
        first.insert(SalonVisit(shop: shop.id, client: a.id, service: service.id,
            stylist: stylist.name, start: start, end: start.addingTimeInterval(1_800), walkIn: false))
        second.insert(SalonVisit(shop: shop.id, client: b.id, service: service.id,
            stylist: stylist.name, start: start.addingTimeInterval(200),
            end: start.addingTimeInterval(1_200), walkIn: false))
        try first.save(); try second.save()
        XCTAssertThrowsError(try CloudOperationalSync.merge(try export(first, shop: shop),
            shop: other, cloudUserID: "same-iCloud", context: second))
        second.rollback()
        XCTAssertEqual(try second.fetchCount(FetchDescriptor<SalonVisit>()), 1)
    }
}
