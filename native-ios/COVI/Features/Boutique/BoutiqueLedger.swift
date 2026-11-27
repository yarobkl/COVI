import SwiftData
import Foundation

enum Tender: String, CaseIterable {
    case cash = "Espèces"
    case airtel = "Airtel Money"
    case mtn = "MTN MoMo"
    case orange = "Orange Money"
    case moov = "Moov Money"
    case other = "Autre moyen reçu en caisse"

    var isMobileMoney: Bool {
        switch self {
        case .airtel, .mtn, .orange, .moov: true
        case .cash, .other: false
        }
    }
}

@Model final class Bale {
    @Attribute(.unique) var id: UUID
    var shop: UUID
    var label: String
    var cost: Int64
    var costKnown: Bool = true
    var knownCost: Int64? { costKnown ? cost : nil }
    var received: Date
    init(shop: UUID, label: String, cost: Int64?) {
        id = UUID()
        self.shop = shop
        self.label = label
        self.cost = cost ?? 0
        self.costKnown = cost != nil
        received = .now
    }
}

enum BoutiqueError: LocalizedError {
    case invalid, stock, permission, changed
    var errorDescription: String? {
        switch self {
        case .invalid: "Vérifiez les quantités, les montants et la confirmation."
        case .stock: "Le stock disponible est insuffisant."
        case .permission: "Accès expiré. Déverrouillez la caisse."
        case .changed: "Le panier a changé. Vérifiez le nouveau total."
        }
    }
}

@MainActor enum BoutiqueLedger {
    struct Line {
        let product: CatalogItem
        let units: Int

        @MainActor var subtotal: Int64? {
            guard units > 0, product.priceMinor >= 0 else { return nil }
            let (amount, overflow) = product.priceMinor.multipliedReportingOverflow(by: Int64(units))
            return overflow ? nil : amount
        }
    }
    static func total(_ lines: [Line], discount: Int64) throws -> Int64 {
        guard !lines.isEmpty, discount >= 0 else { throw BoutiqueError.invalid }
        var sum: Int64 = 0
        var unique = Set<UUID>()
        for line in lines {
            guard unique.insert(line.product.id).inserted else { throw BoutiqueError.invalid }
            guard let value = line.subtotal else { throw BoutiqueError.invalid }
            let (next, exceeds) = sum.addingReportingOverflow(value)
            guard !exceeds else { throw BoutiqueError.invalid }
            sum = next
        }
        guard discount < sum else { throw BoutiqueError.invalid }
        return sum - discount
    }

    @discardableResult static func sell(_ lines: [Line], discount: Int64, quote: Int64, tender: Tender, received: Int64?,
                     confirmed: Bool, shop: Establishment, actor: UUID, pin: PINManager, context: ModelContext) throws -> CommerceOrder {
        guard try StaffAccess.mayTakePayment(actor: actor, in: shop, context: context),
              pin.mayOperate(shop: shop, actor: actor) else { throw BoutiqueError.permission }
        let due = try total(lines, discount: discount)
        guard due == quote else { throw BoutiqueError.changed }
        guard tender == .cash ? (received ?? -1) >= due : confirmed else { throw BoutiqueError.invalid }
        for line in lines {
            let item = line.product
            guard item.establishmentID == shop.id, !item.isService, !item.soldOut,
                  item.stockReserved >= 0,
                  item.stockOnHand >= item.stockReserved, item.stockOnHand - item.stockReserved >= line.units
            else { throw BoutiqueError.stock }
        }
        let order = CommerceOrder(establishmentID: shop.id, createdByID: actor)
        order.totalMinor = due
        order.discountMinor = discount
        order.state = .completed
        context.insert(order)
        for line in lines {
            let item = line.product
            let detail = OrderLine(orderID: order.id, catalogItemID: item.id, quantity: line.units,
                                   unitPriceMinor: item.priceMinor)
            detail.dishName = item.title
            context.insert(detail)
            item.stockOnHand -= line.units
            item.updatedAt = .now
            context.insert(StockMovement(establishmentID: shop.id, itemID: item.id, delta: -line.units,
                                         reason: "Vente · " + order.id.uuidString, actorID: actor))
        }
        let payment = PaymentRecord(orderID: order.id, establishmentID: shop.id, method: tender.rawValue, amountMinor: due, confirmedByID: actor)
        payment.cashReceived = tender == .cash ? received : nil
        context.insert(payment)
        do {
            try BusinessOutbox.enqueue(kind: "boutique.sale.completed", establishmentID: shop.id,
                entityID: order.id, actorID: actor, relatedIDs: [payment.id], in: context)
            try context.save()
            pin.touch()
            return order
        } catch { context.rollback(); throw error }
    }
}
