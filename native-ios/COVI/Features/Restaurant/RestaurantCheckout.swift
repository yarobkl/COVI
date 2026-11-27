import SwiftUI
import SwiftData

struct RestaurantCheckout: View {
    private enum Mode: String, CaseIterable {
        case partial = "Paiement partiel"
        case full = "Solde complet"
    }

    let table: DiningTable
    let order: CommerceOrder
    let service: RestaurantService
    @Query private var payments: [PaymentRecord]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var mode = Mode.full
    @State private var tender = Tender.cash
    @State private var amountText = ""
    @State private var confirmed = false
    @State private var saved = false
    @State private var message = ""
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    init(table: DiningTable, order: CommerceOrder, service: RestaurantService) {
        self.table = table
        self.order = order
        self.service = service
        let id = order.id
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.orderID == id })
    }

    private var due: Int64? { RestaurantBill.remaining(order, payments: payments) }
    private var typedAmount: Int64? {
        Int64(amountText.filter { !$0.isWhitespace })
    }
    private var canSubmit: Bool {
        guard !saved, let due, due > 0 else { return false }
        if mode == .partial {
            guard let typedAmount, typedAmount > 0, typedAmount < due else { return false }
        }
        return tender == .cash ? (mode == .partial || (typedAmount ?? -1) >= due) : confirmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Encaissement · \(table.label)")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Annuler") { dismiss() }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                balance
                modePicker
                COVICard {
                    VStack(spacing: 0) {
                        tenderRow(.cash, icon: "banknote")
                        Divider()
                        tenderRow(.airtel, icon: "iphone")
                        Divider()
                        tenderRow(.mtn, icon: "iphone")
                        Divider()
                        DisclosureGroup("Autres moyens") {
                            ForEach([Tender.orange, .moov, .other], id: \.self) { option in
                                tenderRow(option, icon: option.isMobileMoney ? "iphone" : "creditcard")
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                    }
                }
                if mode == .partial || tender == .cash {
                    amountField
                }
                if tender != .cash {
                    Toggle("J’ai vérifié la réception de ce paiement", isOn: $confirmed)
                        .padding(.vertical, 4)
                }
                if mode == .partial {
                    partialPreview
                } else if tender == .cash, let typedAmount, let due, typedAmount >= due {
                    LabeledContent("Monnaie à rendre", value: money(typedAmount - due))
                        .font(.subheadline.weight(.semibold))
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(16)
        }
        .background(COVITheme.cream)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            COVIButton(mode == .partial ? "Confirmer l’encaissement partiel" : "Confirmer le solde") {
                if let due { submit(expectedDue: due) }
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(COVITheme.cream)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: mode) { _, next in
            resetInput()
#if DEBUG && targetEnvironment(simulator)
            if diagnostics?.scenario == .restaurantPayment, next == .partial { amountText = "15 000" }
#endif
        }
        .onChange(of: tender) { _, _ in
            confirmed = false
            if mode == .full { amountText = "" }
            message = ""
        }
        .onChange(of: amountText) { _, _ in confirmed = false }
        .onChange(of: due) { _, _ in
            guard !saved else { return }
            resetInput()
            message = RestaurantFault.balanceChanged.localizedDescription
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, [.restaurantPayment, .restaurantFloorCheckoutSheet].contains(diagnostics.scenario) {
                if diagnostics.scenario == .restaurantPayment { mode = .partial }
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var balance: some View {
        let title = due.map { "Reste dû : " + money($0) } ?? "Reste dû à vérifier"
        return Label(title, systemImage: "cylinder")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
    }

    private var modePicker: some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(Mode.allCases, id: \.self) { option in
                let selected = mode == option
                Button { mode = option } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? .white : COVITheme.navy)
                        .background(selected ? COVITheme.navy : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tenderRow(_ option: Tender, icon: String) -> some View {
        Button { tender = option } label: {
            HStack(spacing: 10) {
                Label(option.rawValue, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Image(systemName: tender == option ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tender == option ? .isSelected : [])
    }

    private var amountField: some View {
        let title = mode == .partial ? "Montant encaissé" : "Espèces reçues"
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return COVICard {
            layout {
                Label(title, systemImage: "cylinder").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(title)
                    Text(service.shop.currencyCode == "XAF" ? "FCFA" : service.shop.currencyCode)
                }
                .font(.subheadline.weight(.semibold))
                .padding(8)
                .background(COVITheme.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var partialPreview: some View {
        let remainder = due.flatMap { due in typedAmount.flatMap { $0 > 0 && $0 < due ? due - $0 : nil } }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let remainder {
                    Text("Nouveau reste dû : \(money(remainder))").font(.subheadline.bold())
                }
                Text("La table reste ouverte. Terminez le règlement sur cet appareil.")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetInput() {
        confirmed = false
        amountText = ""
        message = ""
    }

    private func money(_ amount: Int64) -> String {
        COVIMoney.text(amount, currency: service.shop.currencyCode)
    }

    private func submit(expectedDue: Int64) {
        guard canSubmit else { return }
        do {
            if mode == .partial, let typedAmount {
                try service.recordPartialPayment(table, order: order, tender: tender,
                    amount: typedAmount, confirmed: confirmed, expectedDue: expectedDue)
            } else {
                try service.finish(table, order: order, paid: true, tender: tender,
                    received: typedAmount, confirmed: confirmed, expectedDue: expectedDue)
            }
            saved = true
            HapticService.confirm()
            dismiss()
        } catch {
            message = error.localizedDescription
            confirmed = false
            HapticService.error()
        }
    }
}
