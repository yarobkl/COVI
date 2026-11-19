import Foundation

struct ReceiptSummary {
    struct Line: Identifiable {
        let id: UUID
        let name: String
        let quantity: Int
        let unitPriceMinor: Int64
        let amountMinor: Int64
    }

    let orderID: UUID
    let shopName: String
    let city: String
    let currencyCode: String
    let date: Date
    let lines: [Line]
    let subtotalMinor: Int64
    let discountMinor: Int64
    let totalMinor: Int64
    let method: String
    let confirmedAt: Date

    var shareText: String {
        var output = [
            "COVI · Reçu de paiement",
            shopName + " · " + city,
            "Commande " + String(orderID.uuidString.prefix(8)),
            date.formatted(date: .abbreviated, time: .shortened), ""
        ]
        output += lines.map { "\($0.quantity) × \($0.name) — \($0.amountMinor) \(currencyCode)" }
        output += [
            "",
            "Sous-total : \(subtotalMinor) \(currencyCode)",
            "Remise : \(discountMinor) \(currencyCode)",
            "TOTAL : \(totalMinor) \(currencyCode)",
            "Règlement : " + method,
            "Paiement confirmé en caisse le " + confirmedAt.formatted(date: .abbreviated, time: .shortened)
        ]
        return output.joined(separator: "\n")
    }
}

enum ReceiptBuilder {
    enum Fault: LocalizedError {
        case noPayment, mismatchedTotal, invalidOrder
        var errorDescription: String? {
            switch self {
            case .noPayment: "Le règlement de cette vente n'a pas encore été confirmé."
            case .mismatchedTotal: "Les montants du reçu doivent être vérifiés avant partage."
            case .invalidOrder: "Cette commande ne peut pas produire de reçu."
            }
        }
    }

    static func create(order: CommerceOrder, shop: Establishment, lines: [OrderLine],
                       products: [CatalogItem], payments: [PaymentRecord]) throws -> ReceiptSummary {
        guard order.establishmentID == shop.id, order.state == .completed,
              order.totalMinor > 0, order.discountMinor >= 0 else { throw Fault.invalidOrder }
        let paid = payments.filter { $0.orderID == order.id && $0.establishmentID == shop.id }
        guard !paid.isEmpty, paid.allSatisfy({ $0.amountMinor > 0 }) else { throw Fault.noPayment }
        let orderLines = lines.filter { $0.orderID == order.id }
        guard !orderLines.isEmpty else { throw Fault.invalidOrder }

        var subtotal: Int64 = 0
        let rows = try orderLines.map { line -> ReceiptSummary.Line in
            guard line.quantity > 0, line.unitPriceMinor >= 0 else { throw Fault.mismatchedTotal }
            let (amount, overflow) = line.unitPriceMinor.multipliedReportingOverflow(by: Int64(line.quantity))
            let (next, exceeds) = subtotal.addingReportingOverflow(amount)
            guard !overflow, !exceeds else { throw Fault.mismatchedTotal }
            subtotal = next
            let name = line.dishName ?? products.first(where: { $0.id == line.catalogItemID })?.title ?? "Article"
            return ReceiptSummary.Line(id: line.id, name: name, quantity: line.quantity,
                                       unitPriceMinor: line.unitPriceMinor, amountMinor: amount)
        }
        let (computedTotal, overflow) = subtotal.subtractingReportingOverflow(order.discountMinor)
        guard !overflow, computedTotal == order.totalMinor else { throw Fault.mismatchedTotal }
        var paidTotal: Int64 = 0
        for payment in paid {
            let (next, exceeds) = paidTotal.addingReportingOverflow(payment.amountMinor)
            guard !exceeds else { throw Fault.mismatchedTotal }
            paidTotal = next
        }
        guard paidTotal == order.totalMinor else { throw Fault.mismatchedTotal }
        let methods = Array(Set(paid.map(\.method))).sorted().joined(separator: " + ")
        return ReceiptSummary(orderID: order.id, shopName: shop.name, city: shop.city,
                              currencyCode: shop.currencyCode, date: order.createdAt,
                              lines: rows, subtotalMinor: subtotal,
                              discountMinor: order.discountMinor, totalMinor: order.totalMinor,
                              method: methods, confirmedAt: paid.map(\.confirmedAt).max() ?? order.createdAt)
    }
}
