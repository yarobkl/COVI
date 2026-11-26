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
    var confirmationMessage: String {
        switch self {
        case .rename: "Le nouveau nom de l'établissement sera enregistré sur cet iPhone."
        case .enroll: "Un code de caisse sera attribué à l'opérateur sélectionné."
        case .refund: "Confirmez uniquement si le montant a réellement été rendu au client. COVI ne transfère aucun argent."
        }
    }
}

struct OwnerSettings: View {
    let shop: Establishment
    let pinManager: PINManager
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query private var members: [Membership]
    @Query private var accounts: [Account]
    @State private var operatorID: UUID?
    @State private var cashierPIN = ""
    @Query private var payments: [PaymentRecord]
    @Query private var closedOrders: [CommerceOrder]
    @Query private var refunds: [Refund]
    @State private var name = ""
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var command: OwnerCommand?
    @State private var message = ""
    init(shop: Establishment, pinManager: PINManager) {
        self.shop = shop
        self.pinManager = pinManager
        let shopID = shop.id
        let completed = OrderState.completed.rawValue
        _closedOrders = Query(filter: #Predicate<CommerceOrder> {
            $0.establishmentID == shopID && $0.stateRaw == completed
        })
    }

    private var refundablePayments: [PaymentRecord] {
        let closed = Set(closedOrders.map(\.id))
        let refunded = Set(refunds.map(\.paymentID))
        return payments.filter {
            $0.establishmentID == shop.id && $0.amountMinor > 0 && !refunded.contains($0.id) &&
            (shop.kind != .restaurant || closed.contains($0.orderID))
        }
    }

    var body: some View {
        Form {
            if !pinManager.hasConfiguredPIN(for: .master(ownerID: shop.ownerID)) {
                Section("PIN maître facultatif") {
                    Text("Vous pouvez gérer votre établissement sans ce code. Si vous l'ajoutez, il sera demandé pour les modifications sensibles.")
                        .font(.footnote).foregroundStyle(.secondary)
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
            Section("Sécurité de caisse · facultative") {
                Text("En tant que propriétaire, vous pouvez encaisser directement. Un code à quatre chiffres devient obligatoire seulement si vous choisissez d'en attribuer un.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Opérateur", selection: $operatorID) {
                    Text("Choisir").tag(nil as UUID?)
                    Text("Propriétaire").tag(Optional(shop.ownerID))
                    ForEach(members.filter { $0.active && $0.establishmentID == shop.id && $0.accountID != shop.ownerID }) { member in
                        Text(accounts.first(where: { $0.id == member.accountID })?.fullName ??
                             "Collaborateur " + String(member.accountID.uuidString.prefix(8)))
                            .tag(Optional(member.accountID))
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
                ForEach(refundablePayments) { payment in
                    Button("Rembourser \(payment.amountMinor) \(shop.currencyCode) · \(String(payment.id.uuidString.prefix(8)))") { command = .refund(payment.id) }
                }
            }
            if !message.isEmpty { Text(message) }
        }
        .onAppear { name = shop.name }
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
        .onChange(of: phase) { _, phase in if phase != .active { command = nil; pin = ""; confirmation = "" } }
        .sheet(item: $command) { pending in
            if let configured = try? pinManager.isPINConfigured(for: .master(ownerID: shop.ownerID)),
               configured {
                PINEntryView(pinManager: pinManager, scope: .master(ownerID: shop.ownerID)) { success in
                    if success { execute(pending) }
                    command = nil
                }
            } else if (try? pinManager.isPINConfigured(for: .master(ownerID: shop.ownerID))) == false {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield").font(.largeTitle)
                        .foregroundStyle(COVITheme.navy)
                    Text("Confirmer l’opération").font(.title3.bold())
                    Text(pending.confirmationMessage)
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Confirmer") { execute(pending); command = nil }
                        .buttonStyle(.borderedProminent)
                    Button("Annuler", role: .cancel) { command = nil }
                }
                .padding(24)
                .presentationDetents([.medium])
            } else {
                ContentUnavailableView("Stockage sécurisé inaccessible", systemImage: "lock.slash",
                    description: Text("L’opération ne peut pas être autorisée. Vérifiez votre iPhone et réessayez."))
            }
        }
    }

    private func execute(_ pending: OwnerCommand) {
        guard command?.id == pending.id, phase == .active, let owner = session.accountID,
              owner == shop.ownerID, !shop.archived else { return }
        switch pending {
        case .enroll(let id):
            guard id == shop.ownerID || members.contains(where: {
                $0.active && $0.establishmentID == shop.id && $0.accountID == id
            }) else { return }
            do { try pinManager.configureCashierPIN(cashierPIN, for: id, shopID: shop.id); message = "Code attribué." }
            catch { message = error.localizedDescription }
            cashierPIN = ""
            return
        case .rename(let value):
            guard !value.isEmpty else { return }
            shop.name = value
            shop.updatedAt = .now
            do { try SyncCoordinator.enqueue(.rename, shop: shop, in: context) }
            catch { context.rollback(); message = "Échec du journal local."; return }
        case .refund(let id):
            guard let payment = refundablePayments.first(where: { $0.id == id }) else {
                message = "Paiement indisponible."
                return
            }
            context.insert(Refund(payment: payment, ownerID: owner))
            do { try SyncCoordinator.enqueue(.refund, shop: shop, payment: payment, in: context) }
            catch { context.rollback(); message = "Échec du journal local."; return }
        }
        do { try context.save(); message = "Opération enregistrée sur cet appareil." }
        catch { context.rollback(); message = "Échec de l’enregistrement." }
    }
}

@MainActor
struct RestaurantTeamAccess: View {
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    @Environment(AppSession.self) private var session
    @Query private var memberships: [Membership]
    @Query private var accounts: [Account]
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    private struct Member: Identifiable {
        let id: UUID
        let name: String
        let role: StaffRole
    }

    init(shop: Establishment, actor: UUID, pin: PINManager) {
        self.shop = shop
        self.actor = actor
        self.pin = pin
        let shopID = shop.id
        _memberships = Query(filter: #Predicate<Membership> { $0.establishmentID == shopID })
    }

    private var currentRole: StaffRole? {
        guard shop.kind == .restaurant, session.accountID == actor else { return nil }
        return StaffAccess.role(for: actor, in: shop, memberships: memberships)
    }

    private var mayViewTeam: Bool { currentRole == .owner || currentRole == .manager }

    private var activeMembers: [Member] {
        let owner = Member(id: shop.ownerID, name: name(for: shop.ownerID, fallback: "Propriétaire"), role: .owner)
        let collaborators = Dictionary(grouping: memberships, by: \.accountID)
            .compactMap { accountID, rows -> Member? in
                guard accountID != shop.ownerID,
                      let role = StaffAccess.role(for: accountID, in: shop, memberships: rows) else { return nil }
                return Member(id: accountID, name: name(for: accountID, fallback: "Collaborateur"), role: role)
            }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
            }
        return [owner] + collaborators
    }

    var body: some View {
        Group {
            if mayViewTeam {
                let members = activeMembers
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Les écrans accessibles dépendent du rôle. Le PIN protège les écrans de caisse sur cet appareil.",
                            systemImage: "info.circle")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                        COVISectionTitle("Membres actifs (\(members.count))")
                        COVICard {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(members) { member in
                                    if member.id != members.first?.id { Divider() }
                                    NavigationLink {
                                        memberDetail(member.id)
                                    } label: {
                                        memberRow(member)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if currentRole == .owner {
                            NavigationLink {
                                OwnerSettings(shop: shop, pinManager: pin)
                                    .navigationTitle("Codes PIN et réglages")
                            } label: {
                                COVICard {
                                    COVIIconRow(symbol: "lock.shield", title: "Codes PIN et réglages",
                                                detail: nil)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(COVITheme.Metrics.screenPadding)
                }
#if DEBUG && targetEnvironment(simulator)
                .task {
                    if let diagnostics, diagnostics.scenario == .restaurantTeam {
                        await diagnostics.signalAfterPresentation()
                    }
                }
#endif
            } else {
                ContentUnavailableView("Accès réservé", systemImage: "lock",
                    description: Text("Le propriétaire et le responsable peuvent consulter l’équipe."))
            }
        }
        .foregroundStyle(COVITheme.navy)
        .background(COVIBackdrop())
        .navigationTitle("Équipe & Accès")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func name(for id: UUID, fallback: String) -> String {
        if session.accountID == id, !session.displayName.isEmpty { return session.displayName }
        return accounts.first { $0.id == id && !$0.fullName.isEmpty }?.fullName ?? fallback
    }

    private func memberRow(_ member: Member) -> some View {
        let initials = String(member.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
        let owner = member.role == .owner
        return HStack(spacing: 10) {
            Text(initials)
                .font(.subheadline.bold())
                .foregroundStyle(owner ? .white : COVITheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 42, height: 42)
                .background(owner ? COVITheme.navy : badgeColor(member.role), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) { memberName(member); roleBadge(member.role) }
                    VStack(alignment: .leading, spacing: 3) { memberName(member); roleBadge(member.role) }
                }
                Text(allowedScreens(member.role))
                    .font(.caption)
                    .foregroundStyle(COVITheme.secondaryText)
                if member.role == .waiter || member.role == .cashier || member.role == .kitchen {
                    Text(pinStatus(member.id))
                        .font(.caption)
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }
            Spacer(minLength: 5)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func memberName(_ member: Member) -> some View {
        Text(member.name).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
    }

    private func roleBadge(_ role: StaffRole) -> some View {
        Text(roleTitle(role))
            .font(.caption.weight(.semibold))
            .foregroundStyle(role == .owner ? .white : COVITheme.navy)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(badgeColor(role), in: Capsule())
    }

    @ViewBuilder private func memberDetail(_ id: UUID) -> some View {
        if mayViewTeam, let member = activeMembers.first(where: { $0.id == id }) {
            ScrollView {
                COVICard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(member.name).font(.title3.bold())
                        roleBadge(member.role)
                        Divider()
                        COVIIconRow(symbol: "list.bullet", title: "Écrans autorisés",
                            detail: allowedScreens(member.role), accessory: nil)
                        COVIIconRow(symbol: "lock", title: "Code de caisse",
                            detail: pinStatus(member.id), accessory: nil)
                    }
                }
                .padding(COVITheme.Metrics.screenPadding)
            }
            .background(COVIBackdrop())
            .navigationTitle("Accès du membre")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Accès indisponible", systemImage: "lock")
        }
    }

    private func allowedScreens(_ role: StaffRole) -> String {
        TabPolicy.tabs(for: shop.kind, role: role).map(\.title).joined(separator: " · ")
    }

    private func pinStatus(_ id: UUID) -> String {
        guard let configured = try? pin.isPINConfigured(for: .cashier(staffID: id, shopID: shop.id)) else {
            return "État du PIN indisponible"
        }
        return configured ? "PIN configuré sur cet iPhone" : "PIN non configuré sur cet iPhone"
    }

    private func badgeColor(_ role: StaffRole) -> Color {
        switch role {
        case .owner: COVITheme.navy
        case .cashier: COVITheme.successTint
        case .kitchen: COVITheme.warningTint
        case .manager, .waiter, .stylist: COVITheme.champagne
        }
    }

    private func roleTitle(_ role: StaffRole) -> String {
        switch role {
        case .owner: "Propriétaire"
        case .manager: "Responsable"
        case .cashier: "Caissier"
        case .waiter: "Serveur"
        case .kitchen: "Cuisine"
        case .stylist: "Coiffure"
        }
    }
}
