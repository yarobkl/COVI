import SwiftUI
import SwiftData

struct RestaurantKitchenBoard: View {
    let tables: [DiningTable]
    let orders: [CommerceOrder]
    let lines: [OrderLine]
    let advance: ([OrderLine], Prep, DiningTable, CommerceOrder) -> Void
    @Query private var accounts: [Account]
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var phase = Prep.cooking

    init(tables: [DiningTable], orders: [CommerceOrder], lines: [OrderLine],
         advance: @escaping ([OrderLine], Prep, DiningTable, CommerceOrder) -> Void) {
        self.tables = tables
        self.orders = orders
        self.lines = lines
        self.advance = advance
    }

    private struct Ticket: Identifiable {
        let table: DiningTable
        let order: CommerceOrder
        let lines: [OrderLine]
        var id: UUID { order.id }
        var firstSentAt: Date? { lines.compactMap(\.sentAt).min() }
    }

    var body: some View {
        let active = Dictionary(grouping: orders.filter { $0.state == .accepted }, by: \.id)
        let byOrder = Dictionary(grouping: lines, by: \.orderID)
        let byPhase = Dictionary(uniqueKeysWithValues: Prep.allCases.map { option in
            (option, tickets(for: option, active: active, byOrder: byOrder))
        })
        let visible = byPhase[phase] ?? []
        let filterLayout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        filterLayout {
            ForEach(Prep.allCases, id: \.self) { option in
                filter(option, count: byPhase[option]?.count ?? 0)
            }
        }

        if visible.isEmpty {
            ContentUnavailableView("Aucun ticket", systemImage: "checkmark.circle",
                description: Text("Les tickets de cet état apparaissent ici."))
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visible) { ticket in
                    ticketCard(ticket, phase: phase)
                }
            }
        }
    }

    private func tickets(for phase: Prep, active: [UUID: [CommerceOrder]],
                         byOrder: [UUID: [OrderLine]]) -> [Ticket] {
        tables.compactMap { table -> Ticket? in
            guard let id = table.activeSessionID, let order = active[id]?.first,
                  order.tableID == table.id, order.establishmentID == table.establishmentID else { return nil }
            let matching = (byOrder[id] ?? []).filter { $0.preparation == phase.rawValue }
            guard !matching.isEmpty else { return nil }
            return Ticket(table: table, order: order, lines: matching)
        }.sorted { lhs, rhs in
            let left = lhs.firstSentAt ?? .distantFuture
            let right = rhs.firstSentAt ?? .distantFuture
            return left == right
                ? lhs.table.label.localizedStandardCompare(rhs.table.label) == .orderedAscending
                : left < right
        }
    }

    private func filter(_ option: Prep, count: Int) -> some View {
        let selected = option == phase
        let title = switch option {
        case .cooking: "À préparer"
        case .ready: "Prêts"
        case .served: "Servis"
        }
        return Button { phase = option } label: {
            Text("\(title) (\(count))")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 5).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? .white : COVITheme.navy)
                .background(selected ? COVITheme.navy : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func ticketCard(_ ticket: Ticket, phase: Prep) -> some View {
        COVICard {
            VStack(alignment: .leading, spacing: 11) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        ticketHeading(ticket)
                        Spacer(minLength: 3)
                        phaseBadge(phase, sentAt: ticket.firstSentAt)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ticketHeading(ticket)
                        phaseBadge(phase, sentAt: ticket.firstSentAt)
                    }
                }
                ForEach(ticket.lines) { line in
                    Text("\(line.quantity) × \(dishName(line))")
                        .font(.subheadline)
                }
                if phase != .served {
                    ticketActions(ticket, phase: phase)
                }
            }
            .foregroundStyle(COVITheme.navy)
        }
    }

    private func ticketHeading(_ ticket: Ticket) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "fork.knife")
                .frame(width: 35, height: 35)
                .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(ticket.table.label).font(.headline)
                if let name = accounts.first(where: { $0.id == ticket.order.createdByID })?.fullName,
                   !name.isEmpty {
                    Text("Ouverte par \(name)").font(.caption).foregroundStyle(COVITheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private func phaseBadge(_ phase: Prep, sentAt: Date?) -> some View {
        if phase == .cooking, let sentAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let minutes = Int(max(0, context.date.timeIntervalSince(sentAt)) / 60)
                badge("Reçu · \(minutes) min", tint: COVITheme.warningTint, color: COVITheme.warning)
            }
        } else {
            badge(phase.rawValue, tint: phase == .ready ? COVITheme.successTint : COVITheme.champagne,
                  color: phase == .ready ? COVITheme.success : COVITheme.navy)
        }
    }

    private func badge(_ title: String, tint: Color, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint, in: Capsule())
    }

    private func ticketActions(_ ticket: Ticket, phase: Prep) -> some View {
        let individualTitle = phase == .cooking ? "Marquer prêt" : "Marquer servi"
        let title = ticket.lines.count > 1
            ? (phase == .cooking ? "Tout marquer prêt" : "Tout marquer servi") : individualTitle
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 5)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if ticket.lines.count > 1 {
                Menu {
                    ForEach(ticket.lines) { line in
                        Button("\(individualTitle) · \(line.quantity) × \(dishName(line))") {
                            advance([line], phase, ticket.table, ticket.order)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Actions par ligne")
            }
            Button(title) { advance(ticket.lines, phase, ticket.table, ticket.order) }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(.white)
                .background(phase == .ready ? COVITheme.success : COVITheme.navy,
                            in: RoundedRectangle(cornerRadius: 11))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func dishName(_ line: OrderLine) -> String { line.dishName ?? "Article" }
}
