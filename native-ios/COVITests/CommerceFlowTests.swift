import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CommerceFlowTests: XCTestCase {
    private func database() throws -> ModelContext {
        let schema = Schema([
            Establishment.self, Membership.self, CatalogItem.self, DiningTable.self, CommerceOrder.self,
            OrderLine.self, PaymentRecord.self, StockMovement.self, OutboxEvent.self,
            SalonClient.self, SalonStaff.self, SalonVisit.self, SalonSaleLine.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        return ModelContext(container)
    }

    private func ownerPIN() -> PINManager {
        PINManager(keychain: KeychainStore(service: "com.covi.app.flow-tests.\(UUID().uuidString)"))
    }

    func testCashSaleDecrementsStockAndCreatesPaymentAndJournal() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Pointe-Noire")
        let item = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_500)
        item.stockOnHand = 10
        db.insert(shop); db.insert(item); try db.save()

        try BoutiqueLedger.sell([.init(product: item, units: 2)], discount: 0, quote: 3_000,
                                tender: .cash, received: 5_000, confirmed: false,
                                shop: shop, actor: owner, pin: ownerPIN(), context: db)
        XCTAssertEqual(item.stockOnHand, 8)
        XCTAssertEqual(try db.fetch(FetchDescriptor<CommerceOrder>()).first?.totalMinor, 3_000)
        XCTAssertEqual(try db.fetch(FetchDescriptor<PaymentRecord>()).first?.cashReceived, 5_000)
        XCTAssertEqual(try db.fetch(FetchDescriptor<StockMovement>()).first?.delta, -2)
        XCTAssertEqual(try db.fetch(FetchDescriptor<OutboxEvent>()).count, 1)
    }

    func testExternalMobilePaymentRequiresCashierConfirmation() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Brazzaville")
        let item = CatalogItem(establishmentID: shop.id, title: "Eau", priceMinor: 500)
        item.stockOnHand = 10
        db.insert(shop); db.insert(item); try db.save()

        XCTAssertThrowsError(try BoutiqueLedger.sell([.init(product: item, units: 1)],
            discount: 0, quote: 500, tender: .airtel, received: nil, confirmed: false,
            shop: shop, actor: owner, pin: ownerPIN(), context: db))
        XCTAssertEqual(item.stockOnHand, 10)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
    }

    func testStockCannotBeOversoldEvenWhenEachLineLooksValid() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Marché", kind: .boutique, city: "Brazzaville")
        let item = CatalogItem(establishmentID: shop.id, title: "Sucre", priceMinor: 100)
        item.stockOnHand = 3
        db.insert(shop); db.insert(item); try db.save()

        let lines = [BoutiqueLedger.Line(product: item, units: 2),
                     BoutiqueLedger.Line(product: item, units: 2)]
        XCTAssertThrowsError(try BoutiqueLedger.sell(lines, discount: 0, quote: 400,
            tender: .cash, received: 400, confirmed: false,
            shop: shop, actor: owner, pin: ownerPIN(), context: db))
        XCTAssertEqual(item.stockOnHand, 3)
    }

    func testSalonBookingRequiresRealActiveCollaborator() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Libreville")
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let service = CatalogItem(establishmentID: shop.id, title: "Coupe", priceMinor: 3_000,
                                  isService: true)
        let collaborator = SalonStaff(shop: shop.id, name: "Coiffeuse")
        db.insert(shop); db.insert(client); db.insert(service); db.insert(collaborator)
        try db.save()
        collaborator.active = false
        XCTAssertThrowsError(try SalonLedger.book(shop: shop.id, actor: owner, client: client,
            item: service, team: collaborator, start: .now, minutes: 30, walkIn: false, db: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<SalonVisit>()), 0)
    }

    func testSameStylistCannotReceiveOverlappingAppointments() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let first = SalonClient(shop: shop.id, name: "Cliente A")
        let second = SalonClient(shop: shop.id, name: "Cliente B")
        let service = CatalogItem(establishmentID: shop.id, title: "Tresses", priceMinor: 8_000,
                                  isService: true)
        let collaborator = SalonStaff(shop: shop.id, name: "Coiffeuse")
        for item in [first, second] { db.insert(item) }
        db.insert(shop); db.insert(service); db.insert(collaborator)
        try db.save()
        let start = Date.now.addingTimeInterval(2 * 3_600)

        try SalonLedger.book(shop: shop.id, actor: owner, client: first, item: service, team: collaborator,
                             start: start, minutes: 60, walkIn: false, db: db)
        XCTAssertThrowsError(try SalonLedger.book(shop: shop.id, actor: owner, client: second,
            item: service, team: collaborator, start: start.addingTimeInterval(30 * 60),
            minutes: 30, walkIn: false, db: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<SalonVisit>()), 1)
    }

    func testSalonRejectsPastAndFarFutureAppointments() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let client = SalonClient(shop: shop.id, name: "Client")
        let service = CatalogItem(establishmentID: shop.id, title: "Coiffure", priceMinor: 2_000,
                                  isService: true)
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeur")
        db.insert(shop); db.insert(client); db.insert(service); db.insert(stylist)
        try db.save()
        for date in [Date.now.addingTimeInterval(-3_600),
                     Date.now.addingTimeInterval(2 * 366 * 24 * 3_600)] {
            XCTAssertThrowsError(try SalonLedger.book(shop: shop.id, actor: owner, client: client,
                item: service, team: stylist, start: date, minutes: 30,
                walkIn: false, db: db))
        }
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<SalonVisit>()), 0)
    }

    func testRestaurantCompleteLifecycleIsIdempotentAtCheckout() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant,
                                 city: "Brazzaville")
        let table = DiningTable(establishmentID: shop.id, label: "Table 1", capacity: 4)
        let dish = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 5_000)
        dish.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(table); db.insert(dish)
        try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)

        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        XCTAssertTrue(table.isOccupied)
        XCTAssertEqual(order.state, .accepted)

        try service.send([dish.id: 2], menu: [dish], table: table, order: order)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        XCTAssertEqual(order.totalMinor, 10_000)
        try service.advance(line, from: .cooking, table: table, order: order)
        try service.advance(line, from: .ready, table: table, order: order)
        try service.finish(table, order: order, paid: false)
        XCTAssertTrue(table.billRequested)
        try service.finish(table, order: order, paid: true)
        XCTAssertFalse(table.isOccupied)
        XCTAssertEqual(order.state, .completed)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)

        XCTAssertThrowsError(try service.finish(table, order: order, paid: true))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 6)
    }

    func testSalonBookingWritesBusinessJournalAndDoesNotDoubleBook() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let item = CatalogItem(establishmentID: shop.id, title: "Tresses", priceMinor: 5_000,
                               isService: true)
        let stylist = SalonStaff(shop: shop.id, name: "Responsable")
        db.insert(shop); db.insert(client); db.insert(item); db.insert(stylist)
        try db.save()
        let start = Date.now.addingTimeInterval(60 * 60)
        try SalonLedger.book(shop: shop.id, actor: owner, client: client, item: item,
                             team: stylist, start: start, minutes: 45, walkIn: false, db: db)
        let event = try XCTUnwrap(db.fetch(FetchDescriptor<OutboxEvent>()).first)
        let payload = try JSONDecoder().decode(BusinessEventPayload.self, from: event.payloadJSON)
        XCTAssertEqual(payload.kind, "salon.appointment.created")
        XCTAssertEqual(payload.establishmentID, shop.id)
        XCTAssertEqual(payload.actorID, owner)
        XCTAssertThrowsError(try SalonLedger.book(shop: shop.id, actor: owner, client: client,
            item: item, team: stylist, start: start, minutes: 45, walkIn: false, db: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 1)
    }
}
