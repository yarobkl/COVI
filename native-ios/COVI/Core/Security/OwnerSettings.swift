import SwiftUI
import SwiftData

@Model final class Refund {
    @Attribute(.unique) var paymentID: UUID
    var establishmentID: UUID
    var ownerID: UUID
    var amountMinor: Int64
    var date: Date
    init(paymentID: UUID, establishmentID: UUID, ownerID: UUID, amountMinor: Int64, date: Date) {
        self.paymentID = paymentID
        self.establishmentID = establishmentID
        self.ownerID = ownerID
        self.amountMinor = amountMinor
        self.date = date
    }
    init(payment: PaymentRecord, ownerID: UUID) {
        paymentID = payment.id
        establishmentID = payment.establishmentID
        amountMinor = payment.amountMinor
        self.ownerID = ownerID
        date = .now
    }
}

private enum OwnerCommand: Identifiable {
    case rename(String), refund(UUID), enroll(UUID)
    var id: String {
        switch self { case .rename(let name): "name-" + name
        case .enroll(let id): "enroll-" + id.uuidString
        case .refund(let id): id.uuidString }
    }
}

struct OwnerSettings: View {
    let shop: Establishment
    let pinManager: PINManager
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query private var members: [Membership]
    @State private var operatorID: UUID?
    @State private var cashierPIN = ""
    @Query private var payments: [PaymentRecord]
    @Query private var refunds: [Refund]
    @State private var name = ""
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var command: OwnerCommand?
    @State private var message = ""
    var body: some View {
        Form {
            if !pinManager.hasConfiguredPIN(for: .master(ownerID: shop.ownerID)) {
                Section("Créer le PIN maître de ce compte") {
                    SecureField("4 chiffres", text: $pin).keyboardType(.numberPad)
                    SecureField("Confirmer", text: $confirmation).keyboardType(.numberPad)
                    Button("Enregistrer le PIN") {
                        defer { pin = ""; confirmation = "" }
                        guard session.accountID == shop.ownerID, !shop.archived, confirmation == pin else { message = "Vérifiez la confirmation."; return }
                        do { try pinManager.configureMasterPIN(pin, ownerID: shop.ownerID); message = "PIN enregistré." }
                        catch { message = error.localizedDescription }
                    }
                }
            }
            Section("Code opérateur") {
                Picker("Opérateur", selection: $operatorID) {
                    Text("Choisir").tag(nil as UUID?)
                    Text("Propriétaire").tag(Optional(shop.ownerID))
                    ForEach(members.filter { $0.active && $0.establishmentID == shop.id && $0.accountID != shop.ownerID }) { member in
                        Text(member.accountID.uuidString).tag(Optional(member.accountID))
                    }
                }
                SecureField("Nouveau PIN de caisse", text: $cashierPIN).keyboardType(.numberPad)
                Button("Attribuer le code") { if let operatorID { command = .enroll(operatorID) } }
                    .disabled(operatorID == nil || cashierPIN.utf8.count != 4 || !cashierPIN.utf8.allSatisfy { (48...57).contains($0) })
            }
            Section("Paramètres") {
                TextField("Nom de l’établissement", text: $name)
                Button("Modifier le nom") { command = .rename(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Remboursements intégraux") {
                ForEach(payments.filter { payment in payment.establishmentID == shop.id && payment.amountMinor > 0 && !refunds.contains { $0.paymentID == payment.id } }) { payment in
                    Button("Rembourser \(payment.amountMinor) \(shop.currencyCode) · \(String(payment.id.uuidString.prefix(8)))") { command = .refund(payment.id) }
                }
            }
            if !message.isEmpty { Text(message) }
        }
        .onAppear { name = shop.name }
        .onChange(of: phase) { _, phase in if phase != .active { command = nil; pin = ""; confirmation = "" } }
        .sheet(item: $command) { pending in
            PINEntryView(pinManager: pinManager, scope: .master(ownerID: shop.ownerID)) { success in
                defer { command = nil }
                guard success, command?.id == pending.id, phase == .active, let owner = session.accountID,
                      owner == shop.ownerID, !shop.archived else { return }
                switch pending {
                case .enroll(let id):
                    guard id == shop.ownerID || members.contains(where: { $0.active && $0.establishmentID == shop.id && $0.accountID == id }) else { return }
                    do { try pinManager.configureCashierPIN(cashierPIN, for: id, shopID: shop.id); message = "Code attribué." }
                    catch { message = error.localizedDescription }
                    cashierPIN = ""
                    return
                case .rename(let value):
                    shop.name = value
                    shop.updatedAt = .now
                    do { try SyncCoordinator.enqueue(.rename, shop: shop, in: context) }
                    catch { context.rollback(); message = "Échec du journal local."; return }
                case .refund(let id):
                    guard let payment = payments.first(where: { $0.id == id && $0.establishmentID == shop.id && $0.amountMinor > 0 }),
                          !refunds.contains(where: { $0.paymentID == id }) else { message = "Paiement indisponible."; return }
                    context.insert(Refund(payment: payment, ownerID: owner))
                    do { try SyncCoordinator.enqueue(.refund, shop: shop, payment: payment, in: context) }
                    catch { context.rollback(); message = "Échec du journal local."; return }
                }
                do { try context.save(); message = "Opération enregistrée sur cet appareil." }
                catch { context.rollback(); message = "Échec de l’enregistrement." }
            }
        }
    }
}
