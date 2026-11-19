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
            menu: [item], tender: .orange, confirmed: false, db: db))
        XCTAssertEqual(item.stockOnHand, 5)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<PaymentRecord>()), 0)
        _ = try SalonLedger.pay(shop: shop, actor: owner, pin: ownerPIN(),
            client: client, team: stylist.name, visit: nil, basket: [item.id: 2],
            menu: [item], tender: .orange, confirmed: true, db: db)
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
