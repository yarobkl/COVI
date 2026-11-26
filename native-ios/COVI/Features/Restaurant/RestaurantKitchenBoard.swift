import SwiftUI
import SwiftData

struct RestaurantKitchenBoard: View {
    let tables: [DiningTable]
    let orders: [CommerceOrder]
    let lines: [OrderLine]
    let advance: ([OrderLine], Prep, DiningTable, CommerceOrder) -> Void
    @Query private var accounts: [Account]
    @Environment(\.dynamicTypeSize) private var textSize
    private enum Filter: String, CaseIterable {
        case queue = "À préparer"
        case ready = "Prêts"
        case served = "Servis"

        var phases: [Prep] {
            switch self {
            case .queue: [.received, .cooking]
            case .ready: [.ready]
            case .served: [.served]
            }
        }
    }
    @State private var selectedFilter = Filter.queue
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

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
        let byFilter = Dictionary(uniqueKeysWithValues: Filter.allCases.map { option in
            (option, tickets(for: option, active: active, byOrder: byOrder))
        })
        let visible = byFilter[selectedFilter] ?? []
        let filterLayout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        filterLayout {
            ForEach(Filter.allCases, id: \.self) { option in
                filter(option, count: byFilter[option]?.count ?? 0)
            }
        }

        if visible.isEmpty {
            ContentUnavailableView("Aucun ticket", systemImage: "checkmark.circle",
                description: Text("Les tickets de cet état apparaissent ici."))
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visible) { ticket in
                    ticketCard(ticket)
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        Color.clear.frame(height: 0)
            .task {
                if let diagnostics, diagnostics.scenario == .restaurantKitchenReady {
                    selectedFilter = .ready
                    await diagnostics.signalAfterPresentation()
                }
            }
#endif
    }

    private func tickets(for filter: Filter, active: [UUID: [CommerceOrder]],
                         byOrder: [UUID: [OrderLine]]) -> [Ticket] {
        tables.compactMap { table -> Ticket? in
            guard let id = table.activeSessionID, let order = active[id]?.first,
                  order.tableID == table.id, order.establishmentID == table.establishmentID else { return nil }
            let matching = (byOrder[id] ?? []).filter { line in
                filter.phases.contains { $0.rawValue == line.preparation }
            }
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

    private func filter(_ option: Filter, count: Int) -> some View {
        let selected = option == selectedFilter
        return Button { selectedFilter = option } label: {
            Text("\(option.rawValue) (\(count))")
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

    private func ticketCard(_ ticket: Ticket) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let pending = ticket.lines.filter { $0.preparation == Prep.received.rawValue }
            let oldest = pending.compactMap(\.sentAt).min()
            let urgent = oldest.map { context.date.timeIntervalSince($0) >= 600 } ?? false
            COVICard {
                VStack(alignment: .leading, spacing: 11) {
                    ticketHeading(ticket)
                    ForEach(selectedFilter.phases, id: \.self) { phase in
                        let current = ticket.lines.filter { $0.preparation == phase.rawValue }
                        if !current.isEmpty {
                            if phase == .cooking && !pending.isEmpty { Divider() }
                            ticketSection(ticket, lines: current, phase: phase, now: context.date, urgent: urgent)
                        }
                    }
                }
                .foregroundStyle(COVITheme.navy)
            }
            .overlay {
                if urgent {
                    RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius)
                        .strokeBorder(COVITheme.warning, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func ticketSection(_ ticket: Ticket, lines: [OrderLine], phase: Prep, now: Date, urgent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let sentAt = lines.compactMap(\.sentAt).min()
            phaseBadge(phase, sentAt: sentAt, now: now)
            ForEach(lines) { line in
                Text("\(line.quantity) × \(dishName(line))")
                    .font(.subheadline)
            }
            if phase != .served {
                ticketActions(ticket, lines: lines, phase: phase, urgent: urgent && phase == .received)
            }
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

    @ViewBuilder private func phaseBadge(_ phase: Prep, sentAt: Date?, now: Date) -> some View {
        switch phase {
        case .received:
            let time = sentAt.map { max(0, now.timeIntervalSince($0) / 60) }
            let age = time.map { " · \(Int(min($0, 99_999))) min" } ?? ""
            badge("Reçu" + age, tint: COVITheme.warningTint, color: COVITheme.warning)
        case .cooking:
            badge("Pris en charge", tint: COVITheme.blue.opacity(0.12), color: COVITheme.blue)
        case .ready:
            badge("Prêt", tint: COVITheme.successTint, color: COVITheme.success)
        case .served:
            badge("Servi", tint: COVITheme.champagne, color: COVITheme.navy)
        }
    }

    private func badge(_ title: String, tint: Color, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint, in: Capsule())
    }

    private func ticketActions(_ ticket: Ticket, lines: [OrderLine], phase: Prep, urgent: Bool) -> some View {
        let individualTitle = switch phase {
        case .received: "Prendre en charge"
        case .cooking: "Marquer prêt"
        case .ready, .served: "Marquer servi"
        }
        let title = switch (phase, lines.count > 1) {
        case (.cooking, true): "Tout marquer prêt"
        case (.ready, true): "Tout marquer servi"
        default: individualTitle
        }
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 5)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if urgent {
                badge("Urgent", tint: COVITheme.warningTint, color: COVITheme.warning)
            }
            if lines.count > 1 {
                Menu {
                    ForEach(lines) { line in
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
            Button(title) { advance(lines, phase, ticket.table, ticket.order) }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(phase == .cooking ? COVITheme.navy : .white)
                .background(phase == .ready ? COVITheme.success : phase == .cooking ? COVITheme.champagne : COVITheme.navy,
                            in: RoundedRectangle(cornerRadius: 11))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func dishName(_ line: OrderLine) -> String { line.dishName ?? "Article" }
}
