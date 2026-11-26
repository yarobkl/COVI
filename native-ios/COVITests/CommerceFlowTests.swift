import Foundation
import SwiftData
import XCTest
@testable import COVI

@MainActor
final class CommerceFlowTests: XCTestCase {
    private func database() throws -> ModelContext {
        let schema = Schema([
            Establishment.self, Membership.self, CatalogItem.self, DiningTable.self, CommerceOrder.self,
            OrderLine.self, PaymentRecord.self, StockMovement.self, Bale.self, OutboxEvent.self,
            SalonClient.self, SalonStaff.self, SalonVisit.self, SalonSaleLine.self,
            ExpenseEntry.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        return ModelContext(container)
    }

    private func ownerPIN() -> PINManager {
        PINManager(keychain: InMemorySecureStore())
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

    func testBoutiqueCashierNeedsAnActiveMembershipEvenWithAnUnlockedPIN() throws {
        let db = try database(), cashier = UUID()
        let shop = Establishment(ownerID: UUID(), name: "Épicerie", kind: .boutique, city: "Brazzaville")
        let otherShop = Establishment(ownerID: shop.ownerID, name: "Boutique", kind: .boutique, city: "Brazzaville")
        let item = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 500)
        item.stockOnHand = 3
        let membership = Membership(accountID: cashier, establishmentID: shop.id, role: .cashier)
        membership.active = false
        db.insert(shop); db.insert(otherShop); db.insert(item); db.insert(membership)
        db.insert(Membership(accountID: cashier, establishmentID: otherShop.id, role: .cashier))
        try db.save()

        let pin = ownerPIN()
        try pin.configureCashierPIN("1234", for: cashier, shopID: shop.id)
        XCTAssertTrue(pin.verify("1234", scope: .cashier(staffID: cashier, shopID: shop.id)))

        func sell() throws {
            try BoutiqueLedger.sell([.init(product: item, units: 1)], discount: 0, quote: 500,
                tender: .cash, received: 500, confirmed: false, shop: shop, actor: cashier, pin: pin, context: db)
        }

        XCTAssertThrowsError(try sell())
        XCTAssertEqual(item.stockOnHand, 3)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)

        membership.active = true
        try db.save()
        try sell()
        XCTAssertEqual(item.stockOnHand, 2)

        membership.active = false
        try db.save()
        XCTAssertThrowsError(try sell())
        XCTAssertEqual(item.stockOnHand, 2)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
    }

    func testRestaurantRechecksTheStoredRoleWhenOperatingAnOpenService() throws {
        let db = try database(), waiter = UUID()
        let shop = Establishment(ownerID: UUID(), name: "Restaurant", kind: .restaurant, city: "Yaoundé")
        let membership = Membership(accountID: waiter, establishmentID: shop.id, role: .waiter)
        db.insert(shop); db.insert(membership); try db.save()

        let pin = ownerPIN()
        try pin.configureCashierPIN("1234", for: waiter, shopID: shop.id)
        XCTAssertTrue(pin.verify("1234", scope: .cashier(staffID: waiter, shopID: shop.id)))
        let service = RestaurantService(shop: shop, actor: waiter, role: .waiter, pin: pin, db: db)
        try service.authorize()

        membership.role = .kitchen
        try db.save()
        XCTAssertThrowsError(try service.authorize())
        try RestaurantService(shop: shop, actor: waiter, role: .kitchen, pin: pin, db: db)
            .authorize(kitchen: true)
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

    func testBoutiqueProductEditsKeepOriginalReceiptAmountsAndNames() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Libreville")
        db.insert(shop)
        let item = try BoutiqueInventoryService.create(shop: shop, name: "Beignets", price: 250,
                                                        actor: owner, context: db)
        item.stockOnHand = 5
        try db.save()
        let sale = try BoutiqueLedger.sell([.init(product: item, units: 2)], discount: 0, quote: 500,
            tender: .cash, received: 1_000, confirmed: false, shop: shop,
            actor: owner, pin: ownerPIN(), context: db)
        try BoutiqueInventoryService.edit(item, in: shop, name: "Beignets maison", price: 300,
                                          actor: owner, context: db)
        XCTAssertEqual(item.title, "Beignets maison")
        XCTAssertEqual(item.priceMinor, 300)
        let lines = try db.fetch(FetchDescriptor<OrderLine>())
        let payments = try db.fetch(FetchDescriptor<PaymentRecord>())
        let receipt = try ReceiptBuilder.create(order: sale, shop: shop, lines: lines,
                                                products: [item], payments: payments)
        XCTAssertEqual(receipt.lines.first?.name, "Beignets")
        XCTAssertEqual(receipt.lines.first?.unitPriceMinor, 250)
        XCTAssertEqual(receipt.totalMinor, 500)
    }

    func testBoutiqueRejectsDuplicateProductNamesAndUnrelatedShopEdits() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Douala")
        let foreign = Establishment(ownerID: UUID(), name: "Autre", kind: .boutique, city: "Douala")
        db.insert(shop); db.insert(foreign)
        let product = try BoutiqueInventoryService.create(shop: shop, name: "Café", price: 500,
                                                           actor: owner, context: db)
        XCTAssertThrowsError(try BoutiqueInventoryService.create(shop: shop, name: "  CAFÉ ",
            price: 600, actor: owner, context: db))
        XCTAssertThrowsError(try BoutiqueInventoryService.edit(product, in: foreign,
            name: "Nouveau", price: 700, actor: owner, context: db))
        XCTAssertEqual(product.title, "Café")
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CatalogItem>()), 1)
    }

    func testBoutiqueCanSuspendAndResumeSalesWithoutDeletingInventoryOrHistory() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Kinshasa")
        let foreign = Establishment(ownerID: UUID(), name: "Autre", kind: .boutique, city: "Libreville")
        db.insert(shop); db.insert(foreign)
        let item = try BoutiqueInventoryService.create(shop: shop, name: "Manioc", price: 300,
            actor: owner, context: db)
        item.stockOnHand = 10
        try db.save()
        let previous = try BoutiqueLedger.sell([.init(product: item, units: 2)],
            discount: 0, quote: 600, tender: .cash, received: 1_000,
            confirmed: false, shop: shop, actor: owner, pin: ownerPIN(), context: db)
        try BoutiqueInventoryService.setAvailability(item, in: shop, available: false,
            actor: owner, context: db)
        XCTAssertTrue(item.soldOut)
        XCTAssertThrowsError(try BoutiqueLedger.sell([.init(product: item, units: 1)],
            discount: 0, quote: 300, tender: .cash, received: 300,
            confirmed: false, shop: shop, actor: owner, pin: ownerPIN(), context: db))
        XCTAssertThrowsError(try BoutiqueInventoryService.setAvailability(item, in: foreign,
            available: true, actor: owner, context: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(item.stockOnHand, 8)
        XCTAssertEqual(previous.totalMinor, 600)
        try BoutiqueInventoryService.setAvailability(item, in: shop, available: true,
            actor: owner, context: db)
        XCTAssertFalse(item.soldOut)
        try BoutiqueInventoryService.setAvailability(item, in: shop, available: true,
            actor: owner, context: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 4)
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

    func testStockOverviewSeparatesAvailableReservedAndOtherShopStock() {
        let shop = UUID()
        let good = CatalogItem(establishmentID: shop, title: "Riz", priceMinor: 1_000)
        good.stockOnHand = 10
        good.stockReserved = 3
        let low = CatalogItem(establishmentID: shop, title: "Huile", priceMinor: 2_000)
        low.stockOnHand = 2
        let foreign = CatalogItem(establishmentID: UUID(), title: "Café", priceMinor: 20_000)
        foreign.stockOnHand = 100
        let summary = StockSnapshot.make(items: [good, low, foreign], shopID: shop)
        XCTAssertEqual(summary.articleCount, 2)
        XCTAssertEqual(summary.suspendedCount, 0)
        XCTAssertEqual(summary.availableUnits, Decimal(9))
        XCTAssertEqual(summary.retailValue, Decimal(11_000))
        XCTAssertEqual(summary.lowStock.map(\.id), [low.id])
        XCTAssertTrue(summary.invalidItems.isEmpty)
    }

    func testStockOverviewHighlightsInconsistentReservationsWithoutInflatingValue() {
        let shop = UUID()
        let broken = CatalogItem(establishmentID: shop, title: "Sucre", priceMinor: 5_000)
        broken.stockOnHand = 2
        broken.stockReserved = 4
        let summary = StockSnapshot.make(items: [broken], shopID: shop)
        XCTAssertEqual(summary.articleCount, 1)
        XCTAssertEqual(summary.availableUnits, .zero)
        XCTAssertEqual(summary.retailValue, .zero)
        XCTAssertEqual(summary.invalidItems.map(\.id), [broken.id])
    }

    func testStockOverviewDoesNotFlagSuspendedCatalogAsActiveShortage() {
        let shop = UUID()
        let item = CatalogItem(establishmentID: shop, title: "Hors saison", priceMinor: 5_000)
        item.soldOut = true
        let summary = StockSnapshot.make(items: [item], shopID: shop)
        XCTAssertEqual(summary.articleCount, 1)
        XCTAssertEqual(summary.suspendedCount, 1)
        XCTAssertTrue(summary.lowStock.isEmpty)
        XCTAssertEqual(summary.availableUnits, .zero)
    }

    func testStockCSVExportsOnlyOwnShopWithSuspendedStatus() {
        let shop = UUID()
        let item = CatalogItem(establishmentID: shop, title: "Riz, local", priceMinor: 1_500)
        item.stockOnHand = 12
        item.stockReserved = 2
        item.soldOut = true
        let foreign = CatalogItem(establishmentID: UUID(), title: "Privé", priceMinor: 1_000)
        let csv = BoutiqueStockOverview.export([item, foreign], shopID: shop)
        XCTAssertTrue(csv.contains("\"Riz, local\""))
        XCTAssertTrue(csv.contains("\"12\",\"2\",\"10\",\"Vente suspendue\""))
        XCTAssertFalse(csv.contains("Privé"))
    }

    func testStockCSVCanExportCorruptQuantityWithoutIntegerOverflow() {
        let shop = UUID()
        let broken = CatalogItem(establishmentID: shop, title: "À contrôler", priceMinor: 500)
        broken.stockOnHand = Int.max
        broken.stockReserved = -1
        let csv = BoutiqueStockOverview.export([broken], shopID: shop)
        XCTAssertTrue(csv.contains("\"Incohérent\""))
        XCTAssertTrue(csv.contains("À contrôler"))
    }

    func testCSVEncodingEscapesQuotesLinesAndSpreadsheetFormulas() {
        let csv = COVICSV.encode(headers: ["Article", "Montant"], rows: [
            [.text("=CONCAT(\"secret\")\nAutre"), .number("-1200")],
            [.text("  @HYPERLINK()"), .number("0")]
        ])
        XCTAssertTrue(csv.contains("\"'=CONCAT(\"\"secret\"\")\nAutre\""))
        XCTAssertTrue(csv.contains("\"'  @HYPERLINK()\""))
        XCTAssertTrue(csv.contains("\"-1200\""))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 3)
    }

    func testExpenseCSVPreservesCancelledEntryAndGuardsFreeformNote() {
        let shop = UUID(), owner = UUID()
        let active = ExpenseEntry(establishmentID: shop, actorID: owner, category: "Transport",
                                  amountMinor: 7_000, spentAt: .now, note: "Taxi")
        let cancelled = ExpenseEntry(establishmentID: shop, actorID: owner, category: "Autre",
                                     amountMinor: 1_500, spentAt: .now, note: "=1+1")
        cancelled.voidedAt = .now
        let csv = ExpenseSpace.export([active, cancelled])
        XCTAssertTrue(csv.contains("\"Transport\",\"7000\",\"Active\",\"Taxi\""))
        XCTAssertTrue(csv.contains("\"Autre\",\"1500\",\"Annulée\",\"'=1+1\""))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 3)
    }

    func testFinanceCSVSeparatesConfirmedIncomeRefundsAndExpenses() {
        let snapshot = FinanceSnapshot(collected: Decimal(10_000), refunded: Decimal(1_000),
            expenses: Decimal(3_000), paymentCount: 2,
            byMethod: [("Espèces", Decimal(7_000)), ("MTN MoMo", Decimal(3_000))],
            byExpense: [("Transport", Decimal(3_000))])
        let csv = FinanceOverview.export(snapshot: snapshot, month: .now, currency: "XAF")
        XCTAssertTrue(csv.contains("\"Encaissements\",\"Confirmés\",\"10000\""))
        XCTAssertTrue(csv.contains("\"Remboursements\",\"Remis\",\"1000\""))
        XCTAssertTrue(csv.contains("\"Solde des flux\",\"Ni bénéfice ni solde bancaire\",\"6000\""))
        XCTAssertTrue(csv.contains("\"XAF\""))
        XCTAssertTrue(csv.contains("\"MTN MoMo\",\"3000\""))
    }

    func testRestaurantTabPolicyListsOnlyScreensCurrentlyGrantedToEachRole() {
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .owner), [.service, .tables, .kitchen, .more])
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .manager), [.service, .tables, .kitchen, .more])
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .waiter), [.service, .tables, .more])
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .kitchen), [.kitchen, .more])
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .cashier), [.more])
        XCTAssertEqual(TabPolicy.tabs(for: .restaurant, role: .stylist), [.more])
    }

    func testRestaurantFloorDrawingKeepsEveryChairVisibleAndSeparate() {
        let size = CGSize(width: 96, height: 96)
        let bounds = CGRect(origin: .zero, size: size)
        for shape in FloorTableDrawing.Shape.allCases {
            for capacity in 1...100 {
                let drawing = FloorTableDrawing(shape: shape, capacity: capacity, size: size)
                XCTAssertEqual(drawing.chairCenters.count, capacity)
                let side = drawing.chairSide
                XCTAssertGreaterThan(side, 0)
                let chairs = drawing.chairCenters.map { point in
                    CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
                }
                for (index, chair) in chairs.enumerated() {
                    XCTAssertTrue(bounds.contains(chair), "\(shape) · Capacité \(capacity)")
                    XCTAssertFalse(chairs.dropFirst(index + 1).contains(where: { $0.intersects(chair) }),
                        "\(shape) · Capacité \(capacity)")
                }
            }
        }
    }

    func testRestaurantFloorLayoutPreservesPositionsDuringSwapsAndReopening() throws {
        let shop = UUID()
        let first = DiningTable(establishmentID: shop, label: "Table 1", capacity: 4)
        let second = DiningTable(establishmentID: shop, label: "Table 2", capacity: 8)
        let third = DiningTable(establishmentID: shop, label: "Table 3", capacity: 6)
        var layout = try RestaurantFloorLayout(stored: Data())
        let tables = [first, second, third]
        XCTAssertEqual(layout.resolved(tables: tables)[second.id]?.slot, 1)
        try layout.place(.init(slot: 8, shape: .oval, rotation: 1), tableID: second.id, tables: tables)
        try layout.place(.init(slot: 8, shape: .round, rotation: 2), tableID: first.id, tables: tables)
        let saved = try RestaurantFloorLayout(stored: layout.encoded())
        let positions = saved.resolved(tables: [third, second, first])
        XCTAssertEqual(positions[first.id], .init(slot: 8, shape: .round, rotation: 2))
        XCTAssertEqual(positions[second.id], .init(slot: 0, shape: .oval, rotation: 1))
        XCTAssertEqual(positions[third.id]?.slot, 2)

        let newTable = DiningTable(establishmentID: shop, label: "Table 4", capacity: 10)
        let updated = saved.resolved(tables: [third, second, first, newTable])
        XCTAssertEqual(updated[newTable.id]?.slot, 1)
        XCTAssertThrowsError(try layout.place(.init(slot: -1, shape: .square), tableID: first.id, tables: tables))
        XCTAssertThrowsError(try layout.place(.init(slot: 0, shape: .square, rotation: 4), tableID: first.id, tables: tables))
        XCTAssertEqual(layout.placements, saved.placements)
    }

    func testRestaurantFloorRoomsPreserveLegacyPositionsAndRejectOccupiedCrossRoomMoves() throws {
        struct LegacyPlacement: Encodable {
            let slot = 5
            let shape = FloorTableDrawing.Shape.square
            let rotation = 1
        }
        let shop = UUID()
        let inside = DiningTable(establishmentID: shop, label: "Table 1", capacity: 4)
        let outside = DiningTable(establishmentID: shop, label: "Table 2", capacity: 6)
        let tables = [inside, outside]
        let legacy = try JSONEncoder().encode(["placements": [inside.id: LegacyPlacement()]])
        var layout = try RestaurantFloorLayout(stored: legacy)
        XCTAssertNil(layout.resolved(tables: tables)[inside.id]?.roomID)
        XCTAssertEqual(layout.resolved(tables: tables)[inside.id]?.slot, 5)
        let terrace = try layout.addRoom(name: " Terrasse ", kind: .outdoor)
        XCTAssertEqual(terrace.name, "Terrasse")
        XCTAssertThrowsError(try layout.addRoom(name: "Terrasse", kind: .indoor))
        XCTAssertThrowsError(try layout.addRoom(name: RestaurantFloorLayout.mainRoomName, kind: .indoor))

        try layout.place(.init(slot: 5, shape: .round, roomID: terrace.id), tableID: outside.id, tables: tables)
        XCTAssertThrowsError(try layout.place(.init(slot: 5, shape: .square, roomID: terrace.id),
                                             tableID: inside.id, tables: tables))
        XCTAssertThrowsError(try layout.place(.init(slot: 0, shape: .square, roomID: UUID()),
                                             tableID: inside.id, tables: tables))
        try layout.renameRoom(terrace.id, name: "Terrasse haute")
        let reopened = try RestaurantFloorLayout(stored: layout.encoded())
        let resolved = reopened.resolved(tables: tables)
        XCTAssertEqual(reopened.spaces.first?.name, "Terrasse haute")
        XCTAssertEqual(reopened.spaces.first?.kind, .outdoor)
        XCTAssertEqual(resolved[inside.id], .init(slot: 5, shape: .square, rotation: 1))
        XCTAssertEqual(resolved[outside.id], .init(slot: 5, shape: .round, roomID: terrace.id))
    }

    func testRestaurantConfirmsPhysicalGuestsWithinCapacityBeforeBilling() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let table = DiningTable(establishmentID: shop.id, label: "Table 3", capacity: 4)
        db.insert(shop)
        db.insert(table)
        try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: ownerPIN(), db: db)
        XCTAssertThrowsError(try service.open(table, guestCount: 5))
        XCTAssertFalse(table.isOccupied)
        XCTAssertThrowsError(try service.open(table, guestCount: 0))
        try service.open(table, guestCount: 2)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        XCTAssertEqual(order.restaurantGuestCount, 2)

        try service.confirmGuests(3, at: table, order: order)
        try service.confirmGuests(3, at: table, order: order)
        XCTAssertThrowsError(try service.confirmGuests(0, at: table, order: order))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 2)
        try service.finish(table, order: order, paid: false)
        XCTAssertThrowsError(try service.confirmGuests(4, at: table, order: order))
        XCTAssertEqual(order.restaurantGuestCount, 3)
    }

    func testRestaurantFloorZoomClampsTheViewportScale() {
        XCTAssertEqual(RestaurantFloorZoom.bounded(0.75), 1)
        XCTAssertEqual(RestaurantFloorZoom.bounded(1.75), 1.75)
        XCTAssertEqual(RestaurantFloorZoom.bounded(4), 2.5)
        XCTAssertEqual(RestaurantFloorZoom.bounded(.nan), 1)
    }

    func testRestaurantFloorUsesRealTableStateBeforeAndAfterBillRequest() {
        let table = DiningTable(establishmentID: UUID(), label: "Table 7", capacity: 4)
        XCTAssertEqual(RestaurantFloorState(table: table, hasOrderLines: false), .available)
        table.isOccupied = true
        XCTAssertEqual(RestaurantFloorState(table: table, hasOrderLines: false), .occupied)
        XCTAssertEqual(RestaurantFloorState(table: table, hasOrderLines: true), .serving)
        table.billRequested = true
        XCTAssertEqual(RestaurantFloorState(table: table, hasOrderLines: true), .checkout)
    }

    func testRestaurantReportKeepsExternalPaymentsSeparateAndTotalsAboveInt64() throws {
        let owner = UUID(), shop = UUID(), otherShop = UUID()
        let date = Date.now
        let priorMonth = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -1, to: date))
        let cashOrder = CommerceOrder(establishmentID: shop, createdByID: owner, tableID: UUID())
        cashOrder.state = .completed
        cashOrder.totalMinor = .max
        let mobileOrder = CommerceOrder(establishmentID: shop, createdByID: owner, tableID: UUID())
        mobileOrder.state = .completed
        mobileOrder.totalMinor = 25
        let cash = PaymentRecord(orderID: cashOrder.id, establishmentID: shop, method: Tender.cash.rawValue,
            amountMinor: .max, confirmedByID: owner)
        let mobile = PaymentRecord(orderID: mobileOrder.id, establishmentID: shop, method: Tender.mtn.rawValue,
            amountMinor: 25, confirmedByID: owner)
        let external = PaymentRecord(orderID: UUID(), establishmentID: shop, method: Tender.other.rawValue,
            amountMinor: 10, confirmedByID: owner)
        let foreign = PaymentRecord(orderID: UUID(), establishmentID: otherShop, method: Tender.cash.rawValue,
            amountMinor: 100, confirmedByID: owner)
        let previous = PaymentRecord(orderID: UUID(), establishmentID: shop, method: Tender.cash.rawValue,
            amountMinor: 8, confirmedByID: owner)
        for payment in [cash, mobile, external, foreign] { payment.confirmedAt = date }
        previous.confirmedAt = priorMonth
        let refund = Refund(payment: previous, ownerID: owner)
        refund.date = date
        let outOfScopeRefund = Refund(payment: foreign, ownerID: owner)
        outOfScopeRefund.date = date

        let report = RestaurantCashReportSnapshot(shop: shop, month: date, orders: [cashOrder, mobileOrder],
            payments: [cash, mobile, external, foreign, previous], refunds: [refund, outOfScopeRefund])

        let maximum = Decimal(Int64.max)
        XCTAssertEqual(report.receipts.map(\.id), [cash.id, mobile.id, external.id])
        XCTAssertEqual(report.gross, maximum + Decimal(35))
        XCTAssertEqual(report.cash, maximum)
        XCTAssertEqual(report.mobile, Decimal(25))
        XCTAssertEqual(report.other, Decimal(10))
        XCTAssertEqual(report.refundCount, 1)
        XCTAssertEqual(report.refunded, Decimal(8))
        XCTAssertEqual(report.net, maximum + Decimal(27))
        XCTAssertEqual(report.tableCount, 2)
        XCTAssertEqual(report.averageTicket, (maximum + Decimal(25)) / Decimal(2))
    }

    func testRestaurantReportCountsSplitBillInItsSettlementMonthOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let november = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 29)))
        let december = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let owner = UUID(), shopID = UUID()
        let order = CommerceOrder(establishmentID: shopID, createdByID: owner, tableID: UUID())
        order.state = .completed
        order.totalMinor = 2_000
        let partial = PaymentRecord(orderID: order.id, establishmentID: shopID,
            method: Tender.cash.rawValue, amountMinor: 1_200, confirmedByID: owner)
        let final = PaymentRecord(orderID: order.id, establishmentID: shopID,
            method: Tender.mtn.rawValue, amountMinor: 800, confirmedByID: owner)
        partial.confirmedAt = november
        final.confirmedAt = december
        let beforeSettlement = RestaurantCashReportSnapshot(shop: shopID, month: november, orders: [order],
            payments: [partial, final], refunds: [], calendar: calendar)
        let afterSettlement = RestaurantCashReportSnapshot(shop: shopID, month: december, orders: [order],
            payments: [partial, final], refunds: [], calendar: calendar)
        XCTAssertEqual(beforeSettlement.cash, 1_200)
        XCTAssertEqual(beforeSettlement.tableCount, 0)
        XCTAssertEqual(afterSettlement.mobile, 800)
        XCTAssertEqual(afterSettlement.tableCount, 1)
        XCTAssertEqual(afterSettlement.averageTicket, 2_000)
    }

    func testCurrencyCanChangeBeforeAnyOperationButNotAfterAnExpense() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Kinshasa")
        db.insert(shop); try db.save()
        XCTAssertTrue(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "USD", db: db))
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "XAF", db: db))
        let cost = ExpenseEntry(establishmentID: shop.id, actorID: owner, category: "Loyer",
                                amountMinor: 50_000, spentAt: .now, note: "")
        db.insert(cost); try db.save()
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
    }

    func testCurrencyChangeIsLockedByProductAndIgnoresOtherShops() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Boutique", kind: .boutique, city: "Goma")
        let other = Establishment(ownerID: owner, name: "Boutique 2", kind: .boutique, city: "Douala")
        let product = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 1_000)
        db.insert(shop); db.insert(other); db.insert(product); try db.save()
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
        XCTAssertTrue(try SupportedCurrency.mayChange(other, to: "CDF", db: db))
    }

    func testCurrencyChangeIsBlockedByBaleAndArchivedShop() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Dépôt", kind: .boutique, city: "Goma")
        db.insert(shop); try db.save()
        XCTAssertTrue(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
        db.insert(Bale(shop: shop.id, label: "Stock initial", cost: 50_000))
        try db.save()
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
        shop.archived = true
        XCTAssertFalse(try SupportedCurrency.mayChange(shop, to: "CDF", db: db))
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

    func testSalonCatalogRechecksRoleBeforePriceStockAndAvailabilityWrites() throws {
        let db = try database(), owner = UUID(), employee = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let membership = Membership(accountID: employee, establishmentID: shop.id, role: .manager)
        db.insert(shop); db.insert(membership); try db.save()
        let product = try SalonLedger.createCatalog(shop: shop, actor: employee, title: "Sérum",
            price: 5_000, service: false, quantity: 5, percent: 10, db: db)
        membership.role = .cashier; try db.save()
        XCTAssertThrowsError(try SalonLedger.editCatalog(product, shop: shop, actor: employee,
            title: "Autre prix", price: 1, percent: 100, db: db))
        XCTAssertThrowsError(try SalonLedger.adjustProductStock(product, shop: shop, actor: employee,
            counted: 100, reason: "Inventaire", db: db))
        XCTAssertThrowsError(try SalonLedger.setCatalogAvailability(product, shop: shop,
            actor: employee, available: false, db: db))
        XCTAssertThrowsError(try SalonLedger.createCatalog(shop: shop, actor: employee, title: "Soin",
            price: 1, service: true, quantity: 0, percent: 0, db: db))
        XCTAssertEqual(product.priceMinor, 5_000)
        XCTAssertEqual(product.stockOnHand, 5)
        XCTAssertFalse(product.soldOut)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 1)
        membership.role = .manager; membership.active = false; try db.save()
        XCTAssertThrowsError(try SalonLedger.editCatalog(product, shop: shop, actor: employee,
            title: "Sérum", price: 6_000, percent: 10, db: db))
    }

    func testSalonCatalogValidatesNamesRatesAndShopOwnership() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let foreign = Establishment(ownerID: UUID(), name: "Autre", kind: .salon, city: "Douala")
        db.insert(shop); db.insert(foreign)
        let service = try SalonLedger.createCatalog(shop: shop, actor: owner, title: " Tresses ",
            price: 5_000, service: true, quantity: 0, percent: 20, db: db)
        XCTAssertEqual(service.title, "Tresses")
        XCTAssertThrowsError(try SalonLedger.createCatalog(shop: shop, actor: owner,
            title: "TRESSES", price: 6_000, service: true, quantity: 0, percent: 20, db: db))
        XCTAssertThrowsError(try SalonLedger.createCatalog(shop: shop, actor: owner,
            title: "Shampoing", price: 2_000, service: true, quantity: 2, percent: 20, db: db))
        XCTAssertThrowsError(try SalonLedger.editCatalog(service, shop: foreign, actor: owner,
            title: "Intrus", price: 5_000, percent: 30, db: db))
        XCTAssertThrowsError(try SalonLedger.editCatalog(service, shop: shop, actor: owner,
            title: "Tresses", price: 5_000, percent: 101, db: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CatalogItem>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 1)
    }

    func testSalonCatalogEditKeepsExistingVisitAndPastSaleAuditStable() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Libreville")
        let service = try SalonLedger.createCatalog(shop: shop, actor: owner,
            title: "Coiffure", price: 4_000, service: true, quantity: 0, percent: 20, db: db)
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeuse")
        db.insert(shop); db.insert(client); db.insert(stylist); try db.save()
        try SalonLedger.book(shop: shop.id, actor: owner, client: client, item: service,
            team: stylist, start: Date.now.addingTimeInterval(3_600),
            minutes: 30, walkIn: false, db: db)
        let visit = try XCTUnwrap(db.fetch(FetchDescriptor<SalonVisit>()).first)
        let sale = try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(), client: client,
            team: stylist.name, visit: visit, basket: [service.id: 1], menu: [service],
            tender: .cash, confirmed: true, quote: service.priceMinor, received: service.priceMinor, db: db)
        try SalonLedger.editCatalog(service, shop: shop, actor: owner,
            title: "Nouvelle coiffure", price: 7_000, percent: 25, db: db)
        XCTAssertEqual(visit.service, service.id)
        XCTAssertEqual(sale.totalMinor, 4_000)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        XCTAssertEqual(line.dishName, "Coiffure")
        XCTAssertEqual(line.unitPriceMinor, 4_000)
        let commission = try XCTUnwrap(db.fetch(FetchDescriptor<SalonSaleLine>()).first)
        XCTAssertEqual(commission.commission, 800)
        XCTAssertEqual(commission.percent, 20)
        XCTAssertEqual(service.priceMinor, 7_000)
    }

    func testSalonSuspensionBlocksNewAppointmentsButKeepsPreviouslyBookedServicePayable() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Kinshasa")
        let service = try SalonLedger.createCatalog(shop: shop, actor: owner,
            title: "Coupe", price: 3_000, service: true, quantity: 0, percent: 10, db: db)
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeur")
        db.insert(shop); db.insert(client); db.insert(stylist); try db.save()
        let start = Date.now.addingTimeInterval(3_600)
        try SalonLedger.book(shop: shop.id, actor: owner, client: client, item: service,
            team: stylist, start: start, minutes: 30, walkIn: false, db: db)
        let visit = try XCTUnwrap(db.fetch(FetchDescriptor<SalonVisit>()).first)
        try SalonLedger.setCatalogAvailability(service, shop: shop, actor: owner,
            available: false, db: db)
        XCTAssertThrowsError(try SalonLedger.book(shop: shop.id, actor: owner, client: client,
            item: service, team: stylist, start: start.addingTimeInterval(7_200),
            minutes: 30, walkIn: false, db: db))
        XCTAssertThrowsError(try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [service.id: 1],
            menu: [service], tender: .cash, confirmed: true, quote: service.priceMinor, received: service.priceMinor, db: db))
        let sale = try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: visit, basket: [service.id: 1],
            menu: [service], tender: .cash, confirmed: true, quote: service.priceMinor, received: service.priceMinor, db: db)
        XCTAssertEqual(visit.receipt, sale.id)
        try SalonLedger.setCatalogAvailability(service, shop: shop, actor: owner,
            available: true, db: db)
        XCTAssertFalse(service.soldOut)
    }

    func testSalonProductInventoryCorrectionPreservesMovementsAndRejectsForeignStock() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Douala")
        let foreign = Establishment(ownerID: UUID(), name: "Autre", kind: .salon, city: "Douala")
        db.insert(shop); db.insert(foreign)
        let product = try SalonLedger.createCatalog(shop: shop, actor: owner,
            title: "Crème", price: 1_500, service: false, quantity: 15, percent: 5, db: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<StockMovement>()), 1)
        product.stockReserved = 4
        try db.save()
        XCTAssertThrowsError(try SalonLedger.adjustProductStock(product, shop: shop,
            actor: owner, counted: 3, reason: "Comptage matin", db: db))
        XCTAssertThrowsError(try SalonLedger.adjustProductStock(product, shop: foreign,
            actor: owner, counted: 10, reason: "Comptage matin", db: db))
        try SalonLedger.adjustProductStock(product, shop: shop, actor: owner,
            counted: 10, reason: "Comptage matin", db: db)
        XCTAssertEqual(product.stockOnHand, 10)
        let movements = try db.fetch(FetchDescriptor<StockMovement>())
        XCTAssertEqual(movements.count, 2)
        XCTAssertEqual(movements.reduce(0) { $0 + $1.delta }, 10)
        XCTAssertTrue(movements.contains { $0.delta == -5 })
    }

    func testSalonCashRejectsInsufficientCashAndChangedQuoteWithoutWriting() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Brazzaville")
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let stylist = SalonStaff(shop: shop.id, name: "Chloé")
        let item = CatalogItem(establishmentID: shop.id, title: "Sérum", priceMinor: 5_000)
        item.stockOnHand = 2
        db.insert(shop); db.insert(client); db.insert(stylist); db.insert(item)
        try db.save()
        for cash: Int64? in [nil, 4_999] {
            XCTAssertThrowsError(try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
                client: client, team: stylist.name, visit: nil, basket: [item.id: 1], menu: [item],
                tender: .cash, confirmed: true, quote: 5_000, received: cash, db: db))
        }
        XCTAssertThrowsError(try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [item.id: 1], menu: [item],
            tender: .cash, confirmed: true, quote: 4_000, received: 10_000, db: db))
        XCTAssertEqual(item.stockOnHand, 2)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CommerceOrder>()), 0)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
        let receipt = try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [item.id: 1], menu: [item],
            tender: .cash, confirmed: true, quote: 5_000, received: 10_000, db: db)
        XCTAssertEqual(receipt.totalMinor, 5_000)
        XCTAssertEqual(item.stockOnHand, 1)
        let payment = try XCTUnwrap(db.fetch(FetchDescriptor<PaymentRecord>()).first)
        XCTAssertEqual(payment.cashReceived, 10_000)
        XCTAssertEqual(payment.amountMinor, 5_000)
    }

    func testSalonTotalRejectsOverflowForeignAndMissingArticles() throws {
        let shop = UUID()
        let item = CatalogItem(establishmentID: shop, title: "Soin", priceMinor: Int64.max)
        XCTAssertThrowsError(try SalonLedger.total(basket: [item.id: 2], menu: [item], shop: shop))
        XCTAssertThrowsError(try SalonLedger.total(basket: [item.id: 1], menu: [item], shop: UUID()))
        XCTAssertThrowsError(try SalonLedger.total(basket: [UUID(): 1], menu: [item], shop: shop))
        XCTAssertThrowsError(try SalonLedger.total(basket: [:], menu: [item], shop: shop))
        XCTAssertEqual(try SalonLedger.total(basket: [item.id: 1], menu: [item], shop: shop), Int64.max)
    }

    func testSalonNeverRecordsUnconfirmedMobilePayment() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Libreville")
        let client = SalonClient(shop: shop.id, name: "Cliente")
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeuse")
        let item = CatalogItem(establishmentID: shop.id, title: "Shampooing", priceMinor: 1_500)
        item.stockOnHand = 5
        db.insert(shop); db.insert(client); db.insert(stylist); db.insert(item)
        try db.save()
        XCTAssertThrowsError(try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [item.id: 2],
            menu: [item], tender: .orange, confirmed: false, quote: item.priceMinor * 2, db: db))
        XCTAssertEqual(item.stockOnHand, 5)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
        _ = try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [item.id: 2],
            menu: [item], tender: .orange, confirmed: true, quote: item.priceMinor * 2, db: db)
        XCTAssertEqual(item.stockOnHand, 3)
        XCTAssertEqual(try db.fetch(FetchDescriptor<PaymentRecord>()).first?.method, Tender.orange.rawValue)
    }

    func testExpenseJournalCanRecordAndCancelWithoutErasingHistory() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Libreville")
        db.insert(shop); try db.save()
        let expense = try ExpenseLedger.record(shop: shop, actor: owner, category: "Loyer",
            amount: 50_000, date: .now, note: "Local", context: db)
        XCTAssertEqual(expense.category, "Loyer")
        XCTAssertEqual(expense.amountMinor, 50_000)
        XCTAssertNil(expense.voidedAt)
        try ExpenseLedger.void(expense, shop: shop, actor: owner, context: db)
        XCTAssertNotNil(expense.voidedAt)
        XCTAssertEqual(expense.voidedByID, owner)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<ExpenseEntry>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 2)
        XCTAssertThrowsError(try ExpenseLedger.void(expense, shop: shop, actor: owner, context: db))
    }

    func testExpenseRejectsInvalidAmountAndUnauthorizedCancellation() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Épicerie", kind: .boutique, city: "Douala")
        let other = Establishment(ownerID: UUID(), name: "Autre", kind: .boutique, city: "Douala")
        db.insert(shop); db.insert(other); try db.save()
        XCTAssertThrowsError(try ExpenseLedger.record(shop: shop, actor: owner, category: "Loyer",
            amount: 0, date: .now, note: "", context: db))
        XCTAssertThrowsError(try ExpenseLedger.record(shop: shop, actor: owner, category: "Inconnue",
            amount: 100, date: .now, note: "", context: db))
        let expense = try ExpenseLedger.record(shop: shop, actor: owner, category: "Transport",
            amount: 2_000, date: .now, note: "Bus", context: db)
        XCTAssertThrowsError(try ExpenseLedger.void(expense, shop: shop, actor: UUID(), context: db))
        XCTAssertThrowsError(try ExpenseLedger.void(expense, shop: other, actor: other.ownerID, context: db))
        XCTAssertNil(expense.voidedAt)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 1)
    }

    func testExpenseEntryRequiresOwnerOrActiveManager() throws {
        let db = try database(), owner = UUID(), manager = UUID(), cashier = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Yaoundé")
        let membership = Membership(accountID: manager, establishmentID: shop.id, role: .manager)
        let cashierMembership = Membership(accountID: cashier, establishmentID: shop.id, role: .cashier)
        db.insert(shop); db.insert(membership); db.insert(cashierMembership); try db.save()
        XCTAssertThrowsError(try ExpenseLedger.record(shop: shop, actor: cashier,
            category: "Transport", amount: 1_000, date: .now, note: "", context: db))
        _ = try ExpenseLedger.record(shop: shop, actor: manager,
            category: "Transport", amount: 1_000, date: .now, note: "", context: db)
        membership.active = false
        try db.save()
        XCTAssertThrowsError(try ExpenseLedger.record(shop: shop, actor: manager,
            category: "Transport", amount: 1_000, date: .now, note: "", context: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<ExpenseEntry>()), 1)
    }

    func testFinanceSummarySubtractsRefundsAndOnlyActiveExpenses() {
        let owner = UUID(), shop = UUID()
        let payment = PaymentRecord(orderID: UUID(), establishmentID: shop, method: "MTN MoMo",
                                    amountMinor: 10_000, confirmedByID: owner)
        let refund = Refund(payment: payment, ownerID: owner)
        refund.amountMinor = 3_000
        let expense = ExpenseEntry(establishmentID: shop, actorID: owner,
                                   category: "Transport", amountMinor: 2_000,
                                   spentAt: .now, note: "Livraison")
        let cancelled = ExpenseEntry(establishmentID: shop, actorID: owner,
                                     category: "Loyer", amountMinor: 50_000,
                                     spentAt: .now, note: "Erreur de saisie")
        cancelled.voidedAt = .now
        let summary = FinanceSnapshot.make(shop: shop, month: .now, payments: [payment],
            refunds: [refund], expenses: [expense, cancelled])
        XCTAssertEqual(summary.collected, Decimal(10_000))
        XCTAssertEqual(summary.refunded, Decimal(3_000))
        XCTAssertEqual(summary.expenses, Decimal(2_000))
        XCTAssertEqual(summary.balance, Decimal(5_000))
        XCTAssertEqual(summary.paymentCount, 1)
        XCTAssertEqual(summary.byMethod.first?.0, "MTN MoMo")
    }

    func testFinanceSummaryIsolatesOtherShopsAndMonths() throws {
        let shop = UUID(), other = UUID(), owner = UUID()
        let previousMonth = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -1, to: .now))
        let current = PaymentRecord(orderID: UUID(), establishmentID: shop, method: "Espèces",
                                    amountMinor: 5_000, confirmedByID: owner)
        let old = PaymentRecord(orderID: UUID(), establishmentID: shop, method: "Espèces",
                                amountMinor: 10_000, confirmedByID: owner)
        old.confirmedAt = previousMonth
        let foreign = PaymentRecord(orderID: UUID(), establishmentID: other, method: "Espèces",
                                    amountMinor: 100_000, confirmedByID: owner)
        let snapshot = FinanceSnapshot.make(shop: shop, month: .now,
            payments: [current, old, foreign], refunds: [], expenses: [])
        XCTAssertEqual(snapshot.collected, Decimal(5_000))
        XCTAssertEqual(snapshot.paymentCount, 1)
        XCTAssertEqual(snapshot.balance, Decimal(5_000))
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

    func testCancellingAppointmentFreesTimeSlotAndWritesJournal() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Salon", kind: .salon, city: "Yaoundé")
        let first = SalonClient(shop: shop.id, name: "Cliente 1")
        let second = SalonClient(shop: shop.id, name: "Cliente 2")
        let service = CatalogItem(establishmentID: shop.id, title: "Coupe", priceMinor: 3_000,
                                  isService: true)
        let stylist = SalonStaff(shop: shop.id, name: "Coiffeuse")
        db.insert(shop); db.insert(first); db.insert(second); db.insert(service); db.insert(stylist)
        try db.save()
        let start = Date.now.addingTimeInterval(7_200)
        try SalonLedger.book(shop: shop.id, actor: owner, client: first, item: service,
            team: stylist, start: start, minutes: 60, walkIn: false, db: db)
        let visit = try XCTUnwrap(db.fetch(FetchDescriptor<SalonVisit>()).first)
        try SalonLedger.cancel(shop: shop.id, actor: owner, visit: visit, db: db)
        XCTAssertTrue(visit.cancelled)
        XCTAssertThrowsError(try SalonLedger.cancel(shop: shop.id, actor: owner, visit: visit, db: db))
        try SalonLedger.book(shop: shop.id, actor: owner, client: second, item: service,
            team: stylist, start: start, minutes: 60, walkIn: false, db: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<SalonVisit>()), 2)
        let events = try db.fetch(FetchDescriptor<OutboxEvent>())
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(try events.contains {
            try JSONDecoder().decode(BusinessEventPayload.self, from: $0.payloadJSON).kind ==
                "salon.appointment.cancelled"
        })
    }

    func testPaidSalonAppointmentCannotBeCancelled() throws {
        let db = try database(), owner = UUID()
        let visit = SalonVisit(shop: UUID(), client: UUID(), service: UUID(),
            stylist: "Coiffeuse", start: .now, end: .now.addingTimeInterval(1_800), walkIn: false)
        visit.receipt = UUID()
        db.insert(visit); try db.save()
        XCTAssertThrowsError(try SalonLedger.cancel(shop: visit.shop, actor: owner, visit: visit, db: db))
        XCTAssertFalse(visit.cancelled)
    }

    func testSalonReschedulingReleasesOldSlotAndKeepsOneAppointment() throws {
        let db = try database(), owner = UUID(), shopID = UUID()
        let first = SalonClient(shop: shopID, name: "Cliente A")
        let second = SalonClient(shop: shopID, name: "Cliente B")
        let service = CatalogItem(establishmentID: shopID, title: "Coiffure", priceMinor: 5_000,
                                  isService: true)
        let stylist = SalonStaff(shop: shopID, name: "Coiffeuse")
        db.insert(first); db.insert(second); db.insert(service); db.insert(stylist)
        try db.save()
        let oldSlot = Date.now.addingTimeInterval(7_200)
        let newSlot = oldSlot.addingTimeInterval(7_200)
        try SalonLedger.book(shop: shopID, actor: owner, client: first, item: service,
            team: stylist, start: oldSlot, minutes: 60, walkIn: false, db: db)
        let visit = try XCTUnwrap(db.fetch(FetchDescriptor<SalonVisit>()).first)
        let identifier = visit.id
        try SalonLedger.reschedule(visit, shop: shopID, actor: owner, client: second,
            item: service, team: stylist, start: newSlot, minutes: 90, db: db)
        XCTAssertEqual(visit.id, identifier)
        XCTAssertEqual(visit.client, second.id)
        XCTAssertEqual(visit.start, newSlot)
        XCTAssertEqual(visit.end, newSlot.addingTimeInterval(90 * 60))
        try SalonLedger.book(shop: shopID, actor: owner, client: first, item: service,
            team: stylist, start: oldSlot, minutes: 60, walkIn: false, db: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<SalonVisit>()), 2)
        let events = try db.fetch(FetchDescriptor<OutboxEvent>())
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(try events.contains {
            try JSONDecoder().decode(BusinessEventPayload.self,
                from: $0.payloadJSON).kind == "salon.appointment.rescheduled"
        })
    }

    func testSalonRescheduleRefusesConflictPaidVisitAndForeignEntities() throws {
        let db = try database(), owner = UUID(), shopID = UUID()
        let client = SalonClient(shop: shopID, name: "Cliente")
        let stranger = SalonClient(shop: UUID(), name: "Étrangère")
        let service = CatalogItem(establishmentID: shopID, title: "Coupe", priceMinor: 3_000,
                                  isService: true)
        let stylist = SalonStaff(shop: shopID, name: "Coiffeur")
        db.insert(client); db.insert(stranger); db.insert(service); db.insert(stylist)
        try db.save()
        let start = Date.now.addingTimeInterval(7_200)
        try SalonLedger.book(shop: shopID, actor: owner, client: client, item: service,
            team: stylist, start: start, minutes: 30, walkIn: false, db: db)
        try SalonLedger.book(shop: shopID, actor: owner, client: client, item: service,
            team: stylist, start: start.addingTimeInterval(3_600),
            minutes: 30, walkIn: false, db: db)
        let visits = try db.fetch(FetchDescriptor<SalonVisit>(sortBy: [SortDescriptor(\.start)]))
        let first = try XCTUnwrap(visits.first)
        XCTAssertThrowsError(try SalonLedger.reschedule(first, shop: shopID, actor: owner,
            client: client, item: service, team: stylist,
            start: start.addingTimeInterval(3_600), minutes: 30, db: db))
        XCTAssertThrowsError(try SalonLedger.reschedule(first, shop: shopID, actor: owner,
            client: stranger, item: service, team: stylist,
            start: start.addingTimeInterval(7_200), minutes: 30, db: db))
        XCTAssertEqual(first.start, start)
        stylist.active = false
        XCTAssertThrowsError(try SalonLedger.reschedule(first, shop: shopID, actor: owner,
            client: client, item: service, team: stylist,
            start: start.addingTimeInterval(7_200), minutes: 30, db: db))
        stylist.active = true
        first.receipt = UUID()
        XCTAssertThrowsError(try SalonLedger.reschedule(first, shop: shopID, actor: owner,
            client: client, item: service, team: stylist,
            start: start.addingTimeInterval(7_200), minutes: 30, db: db))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 2)
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
        XCTAssertThrowsError(try service.finish(table, order: order, paid: true))
        try service.finish(table, order: order, paid: true, tender: .mtn, confirmed: true)
        XCTAssertFalse(table.isOccupied)
        XCTAssertEqual(order.state, .completed)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(try db.fetch(FetchDescriptor<PaymentRecord>()).first?.method, Tender.mtn.rawValue)

        XCTAssertThrowsError(try service.finish(table, order: order, paid: true,
                                               tender: .mtn, confirmed: true))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 6)
    }

    func testRestaurantPartialPaymentKeepsBillOpenUntilTheVerifiedRemainderIsPaid() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let table = DiningTable(establishmentID: shop.id, label: "Table 01", capacity: 4)
        let dish = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 14_250)
        dish.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(table); db.insert(dish)
        try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.send([dish.id: 2], menu: [dish], table: table, order: order)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        try service.finish(table, order: order, paid: false)
        XCTAssertThrowsError(try service.recordPartialPayment(table, order: order, tender: .cash,
            amount: 15_000, confirmed: false, expectedDue: 28_500))
        try service.advance(line, from: .cooking, table: table, order: order)
        try service.advance(line, from: .ready, table: table, order: order)
        XCTAssertThrowsError(try service.recordPartialPayment(table, order: order, tender: .cash,
            amount: 28_500, confirmed: false, expectedDue: 28_500))
        XCTAssertThrowsError(try service.recordPartialPayment(table, order: order, tender: .airtel,
            amount: 15_000, confirmed: false, expectedDue: 28_500))

        try service.recordPartialPayment(table, order: order, tender: .cash,
            amount: 15_000, confirmed: false, expectedDue: 28_500)
        XCTAssertTrue(table.isOccupied)
        XCTAssertTrue(table.billRequested)
        XCTAssertEqual(order.state, .accepted)
        let partials = try db.fetch(FetchDescriptor<PaymentRecord>())
        XCTAssertEqual(RestaurantBill.remaining(order, payments: partials), 13_500)
        XCTAssertEqual(partials.first?.cashReceived, 15_000)
        XCTAssertThrowsError(try ReceiptBuilder.create(order: order, shop: shop, lines: [line],
            products: [dish], payments: partials))
        XCTAssertThrowsError(try service.recordPartialPayment(table, order: order, tender: .cash,
            amount: 1_000, confirmed: false, expectedDue: 28_500))
        XCTAssertThrowsError(try service.finish(table, order: order, paid: true, tender: .cash,
            received: 12_000, expectedDue: 13_500))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
        try service.finish(table, order: order, paid: true, tender: .mtn, confirmed: true, expectedDue: 13_500)

        let payments = try db.fetch(FetchDescriptor<PaymentRecord>())
        XCTAssertEqual(Set(payments.map(\.amountMinor)), [13_500, 15_000])
        XCTAssertEqual(RestaurantBill.remaining(order, payments: payments), 0)
        let receipt = try ReceiptBuilder.create(order: order, shop: shop, lines: [line],
            products: [dish], payments: payments)
        XCTAssertEqual(receipt.totalMinor, 28_500)
        XCTAssertEqual(order.state, .completed)
        XCTAssertFalse(table.isOccupied)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 7)
    }

    func testKitchenAdvancesTicketLinesTogetherAndRejectsStaleOrRepeatedLines() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let table = DiningTable(establishmentID: shop.id, label: "Table 1", capacity: 4)
        let dishes = ["Poulet", "Poisson", "Riz"].map { name in
            CatalogItem(establishmentID: shop.id, title: name, priceMinor: 5_000)
        }
        db.insert(shop)
        db.insert(table)
        for dish in dishes {
            dish.menuCategory = MenuGroup.food.rawValue
            db.insert(dish)
        }
        try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        let basket = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, 1) })
        try service.send(basket, menu: dishes, table: table, order: order)
        let lines = try db.fetch(FetchDescriptor<OrderLine>())
        XCTAssertEqual(lines.count, 3)
        let first = try XCTUnwrap(lines.first)
        let pending = Array(lines.dropFirst())
        let another = try XCTUnwrap(pending.first)
        try service.advance(first, from: .cooking, table: table, order: order)
        let events = try db.fetchCount(FetchDescriptor<OutboxEvent>())

        XCTAssertThrowsError(try service.advance(lines, from: .cooking, table: table, order: order))
        XCTAssertThrowsError(try service.advance([another, another], from: .cooking, table: table, order: order))
        XCTAssertTrue(pending.allSatisfy { $0.preparation == Prep.cooking.rawValue })
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), events)

        try service.advance(pending, from: .cooking, table: table, order: order)
        XCTAssertTrue(lines.allSatisfy { $0.preparation == Prep.ready.rawValue })
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), events + pending.count)
    }

    func testRestaurantRejectsUnconfirmedMobilePaymentAndInsufficientCash() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Libreville")
        let table = DiningTable(establishmentID: shop.id, label: "T2", capacity: 2)
        let dish = CatalogItem(establishmentID: shop.id, title: "Plat", priceMinor: 4_000)
        dish.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(table); db.insert(dish); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.send([dish.id: 1], menu: [dish], table: table, order: order)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        try service.advance(line, from: .cooking, table: table, order: order)
        try service.advance(line, from: .ready, table: table, order: order)
        try service.finish(table, order: order, paid: false)

        XCTAssertThrowsError(try service.finish(table, order: order, paid: true,
                                               tender: .airtel, confirmed: false))
        XCTAssertThrowsError(try service.finish(table, order: order, paid: true,
                                               tender: .cash, received: 3_500))
        XCTAssertTrue(table.isOccupied)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)

        try service.finish(table, order: order, paid: true, tender: .cash, received: 5_000)
        let payment = try XCTUnwrap(db.fetch(FetchDescriptor<PaymentRecord>()).first)
        XCTAssertEqual(payment.method, Tender.cash.rawValue)
        XCTAssertEqual(payment.cashReceived, 5_000)
    }

    func testRestaurantCannotRecordPaymentForEmptyTable() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let table = DiningTable(establishmentID: shop.id, label: "T3", capacity: 2)
        db.insert(shop); db.insert(table); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.finish(table, order: order, paid: false)
        XCTAssertThrowsError(try service.finish(table, order: order, paid: true,
                                               tender: .cash, received: 1_000))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
        XCTAssertTrue(table.isOccupied)
    }

    func testRestaurantMenuCreationAndAvailabilityRequireCurrentAdminAndValidItem() throws {
        let db = try database(), owner = UUID(), manager = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let foreignShop = Establishment(ownerID: owner, name: "Autre", kind: .restaurant, city: "Dolisie")
        let membership = Membership(accountID: manager, establishmentID: shop.id, role: .manager)
        db.insert(shop)
        db.insert(foreignShop)
        db.insert(membership)
        try db.save()
        let pin = ownerPIN()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: pin, db: db)
        let foreign = RestaurantService(shop: foreignShop, actor: owner, role: .owner, pin: pin, db: db)

        try service.createMenuItem(title: "  Jus de bissap  ", price: 1_500, category: .drinks)
        let item = try XCTUnwrap(db.fetch(FetchDescriptor<CatalogItem>()).first)
        XCTAssertEqual(item.title, "Jus de bissap")
        XCTAssertEqual(item.menuCategory, MenuGroup.drinks.rawValue)
        XCTAssertThrowsError(try service.createMenuItem(title: "JUS DE BISSAP", price: 1_500, category: .food))
        XCTAssertThrowsError(try foreign.setMenuAvailability(item, available: false))
        XCTAssertFalse(item.soldOut)
        try service.setMenuAvailability(item, available: false)
        try service.setMenuAvailability(item, available: false)
        XCTAssertTrue(item.soldOut)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 2)

        try pin.configureCashierPIN("1234", for: manager, shopID: shop.id)
        XCTAssertTrue(pin.verify("1234", scope: .cashier(staffID: manager, shopID: shop.id)))
        let managerService = RestaurantService(shop: shop, actor: manager, role: .manager, pin: pin, db: db)
        try managerService.setMenuAvailability(item, available: true)
        membership.active = false
        try db.save()
        XCTAssertThrowsError(try managerService.setMenuAvailability(item, available: false))
        XCTAssertThrowsError(try managerService.createMenuItem(title: "Infusion", price: 1_000, category: .drinks))
        XCTAssertFalse(item.soldOut)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<CatalogItem>()), 1)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 3)
    }

    func testRestaurantDrinkStockJournalsAdjustmentsAndProtectsReservedUnits() throws {
        let db = try database(), owner = UUID(), manager = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let other = Establishment(ownerID: owner, name: "Autre", kind: .restaurant, city: "Dolisie")
        let membership = Membership(accountID: manager, establishmentID: shop.id, role: .manager)
        let drink = CatalogItem(establishmentID: shop.id, title: "Bissap", priceMinor: 1_000)
        drink.menuCategory = MenuGroup.drinks.rawValue
        let food = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 2_000)
        food.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(other); db.insert(membership); db.insert(drink); db.insert(food)
        try db.save()
        let pin = ownerPIN()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner, pin: pin, db: db)
        let foreign = RestaurantService(shop: other, actor: owner, role: .owner, pin: pin, db: db)
        XCTAssertThrowsError(try service.adjustDrinkStock(drink, operation: .loss, quantity: 1))
        XCTAssertThrowsError(try service.adjustDrinkStock(drink, operation: .restock, quantity: 0))
        XCTAssertThrowsError(try service.adjustDrinkStock(food, operation: .restock, quantity: 1))
        XCTAssertThrowsError(try foreign.adjustDrinkStock(drink, operation: .restock, quantity: 1))
        try service.adjustDrinkStock(drink, operation: .restock, quantity: 12)
        XCTAssertThrowsError(try service.adjustDrinkStock(drink, operation: .restock, quantity: .max))
        drink.stockReserved = 3
        try db.save()

        try pin.configureCashierPIN("1234", for: manager, shopID: shop.id)
        XCTAssertTrue(pin.verify("1234", scope: .cashier(staffID: manager, shopID: shop.id)))
        let managerService = RestaurantService(shop: shop, actor: manager, role: .manager, pin: pin, db: db)
        XCTAssertThrowsError(try managerService.adjustDrinkStock(drink, operation: .loss, quantity: 10))
        try managerService.adjustDrinkStock(drink, operation: .loss, quantity: 9)
        membership.active = false
        try db.save()
        XCTAssertThrowsError(try managerService.adjustDrinkStock(drink, operation: .restock, quantity: 1))

        XCTAssertEqual(drink.stockOnHand, 3)
        XCTAssertEqual(drink.stockReserved, 3)
        XCTAssertFalse(drink.soldOut)
        let moves = try db.fetch(FetchDescriptor<StockMovement>())
        XCTAssertEqual(moves.count, 2)
        XCTAssertEqual(Set(moves.map(\.itemID)), [drink.id])
        XCTAssertEqual(moves.first { $0.actorID == owner }?.delta, 12)
        XCTAssertEqual(moves.first { $0.actorID == manager }?.delta, -9)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OutboxEvent>()), 2)
    }

    func testRestaurantMenuEditPreservesAlreadySentKitchenTicket() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let table = DiningTable(establishmentID: shop.id, label: "T1", capacity: 4)
        let item = CatalogItem(establishmentID: shop.id, title: "Poulet", priceMinor: 4_000)
        item.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(table); db.insert(item); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.send([item.id: 1], menu: [item], table: table, order: order)
        try service.editMenu(item, title: "Poulet rôti", price: 5_000, category: .food)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        XCTAssertEqual(line.dishName, "Poulet")
        XCTAssertEqual(line.unitPriceMinor, 4_000)
        XCTAssertEqual(order.totalMinor, 4_000)
        XCTAssertEqual(item.title, "Poulet rôti")
        XCTAssertEqual(item.priceMinor, 5_000)
        XCTAssertThrowsError(try service.editMenu(item, title: "  ", price: 1_000, category: .food))
    }

    func testRestaurantTableCanBeRenamedOnlyWhenEmpty() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Douala")
        let table = DiningTable(establishmentID: shop.id, label: "Terrasse", capacity: 2)
        let other = DiningTable(establishmentID: shop.id, label: "Salle", capacity: 4)
        db.insert(shop); db.insert(table); db.insert(other); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        XCTAssertThrowsError(try service.editTable(table, label: "Salle", capacity: 4))
        try service.editTable(table, label: "Grande terrasse", capacity: 6)
        XCTAssertEqual(table.label, "Grande terrasse")
        XCTAssertEqual(table.capacity, 6)
        try service.open(table)
        XCTAssertThrowsError(try service.editTable(table, label: "Terrasse modifiée", capacity: 3))
        XCTAssertEqual(table.label, "Grande terrasse")
    }

    func testRestaurantPaymentWaitsUntilEveryDishIsServed() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Libreville")
        let table = DiningTable(establishmentID: shop.id, label: "T4", capacity: 4)
        let dish = CatalogItem(establishmentID: shop.id, title: "Riz", priceMinor: 2_500)
        dish.menuCategory = MenuGroup.food.rawValue
        db.insert(shop); db.insert(table); db.insert(dish); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        try service.send([dish.id: 1], menu: [dish], table: table, order: order)
        try service.finish(table, order: order, paid: false)
        XCTAssertThrowsError(try service.finish(table, order: order, paid: true,
                                               tender: .cash, received: 3_000))
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
        let line = try XCTUnwrap(db.fetch(FetchDescriptor<OrderLine>()).first)
        try service.advance(line, from: .cooking, table: table, order: order)
        try service.advance(line, from: .ready, table: table, order: order)
        try service.finish(table, order: order, paid: true, tender: .cash, received: 3_000)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 1)
    }

    func testRestaurantRefusesSoldOutDishesAndLateAdditionsAfterBill() throws {
        let db = try database(), owner = UUID()
        let shop = Establishment(ownerID: owner, name: "Restaurant", kind: .restaurant, city: "Brazzaville")
        let table = DiningTable(establishmentID: shop.id, label: "T5", capacity: 4)
        let dish = CatalogItem(establishmentID: shop.id, title: "Poisson", priceMinor: 3_500)
        dish.menuCategory = MenuGroup.food.rawValue
        dish.soldOut = true
        db.insert(shop); db.insert(table); db.insert(dish); try db.save()
        let service = RestaurantService(shop: shop, actor: owner, role: .owner,
                                        pin: ownerPIN(), db: db)
        try service.open(table)
        let order = try XCTUnwrap(db.fetch(FetchDescriptor<CommerceOrder>()).first)
        XCTAssertThrowsError(try service.send([dish.id: 1], menu: [dish], table: table, order: order))
        dish.soldOut = false
        try service.send([dish.id: 1], menu: [dish], table: table, order: order)
        try service.finish(table, order: order, paid: false)
        XCTAssertThrowsError(try service.send([dish.id: 1], menu: [dish], table: table, order: order))
        XCTAssertEqual(order.totalMinor, 3_500)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<OrderLine>()), 1)
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

    func testSalonClientNameAndPhoneAreEditableWithAuditHistory() throws {
        let db = try database(), owner = UUID(), shopID = UUID()
        let client = SalonClient(shop: shopID, name: "Ancien nom")
        db.insert(client); try db.save()
        try SalonLedger.updateClient(client, shop: shopID, actor: owner,
            name: " Nouveau nom ", phone: " +241 01 23 45 67 ",
            notes: "Préférence douce", preferences: "Sans produits parfumés", db: db)
        XCTAssertEqual(client.name, "Nouveau nom")
        XCTAssertEqual(client.phone, "+241 01 23 45 67")
        XCTAssertEqual(client.notes, "Préférence douce")
        let event = try XCTUnwrap(db.fetch(FetchDescriptor<OutboxEvent>()).first)
        XCTAssertEqual(try JSONDecoder().decode(BusinessEventPayload.self,
            from: event.payloadJSON).kind, "salon.client.updated")
        XCTAssertThrowsError(try SalonLedger.updateClient(client, shop: UUID(), actor: owner,
            name: "Intrus", phone: "", notes: "", preferences: "", db: db))
        XCTAssertThrowsError(try SalonLedger.updateClient(client, shop: shopID, actor: owner,
            name: " ", phone: "", notes: "", preferences: "", db: db))
        XCTAssertEqual(client.name, "Nouveau nom")
    }
}
