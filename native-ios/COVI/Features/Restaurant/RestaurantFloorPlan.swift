import SwiftUI

enum RestaurantFloorState: String, CaseIterable {
    case available = "Disponible"
    case occupied = "Occupée"
    case serving = "En service"
    case checkout = "À encaisser"

    init(table: DiningTable, hasOrderLines: Bool) {
        if table.billRequested { self = .checkout }
        else if !table.isOccupied { self = .available }
        else { self = hasOrderLines ? .serving : .occupied }
    }

    var tint: Color {
        switch self {
        case .available: COVITheme.successTint
        case .occupied: COVITheme.warningTint
        case .serving: Color(red: 0.85, green: 0.92, blue: 1)
        case .checkout: COVITheme.champagne
        }
    }

    var outline: Color {
        switch self {
        case .available: COVITheme.success
        case .occupied: COVITheme.warning
        case .serving: COVITheme.blue
        case .checkout: COVITheme.navy
        }
    }
}

struct FloorTableDrawing {
    enum Shape: String, CaseIterable, Codable {
        case round = "Ronde"
        case oval = "Ovale"
        case square = "Carrée"
        case rectangle = "Rectangulaire"

        init(capacity: Int) {
            switch capacity {
            case 1: self = .round
            case 2...3: self = .oval
            case 4: self = .square
            default: self = .rectangle
            }
        }
    }

    let surface: CGRect
    let chairCenters: [CGPoint]
    let chairSide: CGFloat
    let cornerRadius: CGFloat

    init(shape: Shape, capacity: Int, size: CGSize) {
        let capacity = max(1, capacity)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shortest = min(size.width, size.height)
        let width: CGFloat
        let height: CGFloat
        switch shape {
        case .round:
            width = shortest * 0.56
            height = width
        case .oval:
            width = size.width * 0.68
            height = shortest * 0.48
        case .square:
            width = shortest * 0.57
            height = width
        case .rectangle:
            width = size.width * 0.86
            height = shortest * 0.47
        }
        let surface = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        self.surface = surface
        cornerRadius = shape == .round || shape == .oval ? height / 2 : 10
        let gap = shortest * 0.082
        let preferredChairSide = min(13, shortest * 0.15)
        if shape == .rectangle {
            let topCount = (capacity + 1) / 2
            let bottomCount = capacity / 2
            chairSide = min(preferredChairSide, width / CGFloat(topCount) * 0.72)
            chairCenters = [(topCount, surface.minY - gap), (bottomCount, surface.maxY + gap)].flatMap { count, y in
                (0..<count).map { i in
                    let x = surface.minX + width * (CGFloat(i) + 0.5) / CGFloat(count)
                    return CGPoint(x: x, y: y)
                }
            }
        } else if shape == .square {
            let largestSide = (capacity + 3) / 4
            chairSide = min(preferredChairSide, width / CGFloat(largestSide) * 0.72)
            chairCenters = (0..<4).flatMap { edge in
                let count = capacity / 4 + (edge < capacity % 4 ? 1 : 0)
                return (0..<count).map { i in
                    let offset = width * (CGFloat(i) + 0.5) / CGFloat(count)
                    switch edge {
                    case 0: return CGPoint(x: surface.minX + offset, y: surface.minY - gap)
                    case 1: return CGPoint(x: surface.maxX + gap, y: surface.minY + offset)
                    case 2: return CGPoint(x: surface.minX + offset, y: surface.maxY + gap)
                    default: return CGPoint(x: surface.minX - gap, y: surface.minY + offset)
                    }
                }
            }
        } else {
            let rx = width / 2 + gap
            let ry = height / 2 + gap
            let minSpacing = capacity > 1 ? 2 * min(rx, ry) * sin(.pi / CGFloat(capacity)) : preferredChairSide * 2
            chairSide = min(preferredChairSide, minSpacing * 0.65)
            chairCenters = (0..<capacity).map { i in
                let angle = 2 * .pi * CGFloat(i) / CGFloat(capacity) - .pi / 2
                return CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
            }
        }
    }
}

struct RestaurantFloorPlan<Detail: View>: View {
    let tables: [DiningTable]
    let orders: [CommerceOrder]
    let lines: [OrderLine]
    let payments: [PaymentRecord]
    let service: RestaurantService
    private let detail: (DiningTable) -> Detail
    @AppStorage private var layoutData: Data
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: UUID?
    @State private var highlightedState: RestaurantFloorState?
    @State private var editingTable: DiningTable?
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    @State private var diagnosticLayout: Data?
#endif

    init(tables: [DiningTable], orders: [CommerceOrder], lines: [OrderLine], payments: [PaymentRecord],
         service: RestaurantService, @ViewBuilder detail: @escaping (DiningTable) -> Detail) {
        self.tables = tables
        self.orders = orders
        self.lines = lines
        self.payments = payments
        self.service = service
        self.detail = detail
        _layoutData = AppStorage(wrappedValue: Data(), "covi.floor-plan.v1." + service.shop.id.uuidString)
    }

    private var orderedTables: [DiningTable] {
        tables.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    plan
                }
                .padding(18)
            }
            .onChange(of: selectedID) { _, id in
                guard id != nil else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                    scroll.scrollTo("restaurant-table-summary", anchor: .bottom)
                }
            }
#if DEBUG && targetEnvironment(simulator)
            .task {
                if let diagnostics, [.restaurantFloorPlan, .restaurantFloorEdit].contains(diagnostics.scenario),
                   let sample = tables.first(where: { $0.label == "Table 10" }) {
                    if let staged = try? sampleLayout(table: sample) { diagnosticLayout = staged }
                    selectedID = sample.id
                    if diagnostics.scenario == .restaurantFloorEdit { editingTable = sample }
                    else { await diagnostics.signalAfterPresentation() }
                }
            }
#endif
        }
        .sheet(item: $editingTable) { table in
            let current = resolvedLayout
            if let placement = current[table.id] {
                RestaurantFloorEditor(table: table, placement: placement, lastSlot: current.values.map(\.slot).max() ?? 0) {
                    try savePlacement($0, tableID: table.id)
                }
            }
        }
    }

    private var resolvedLayout: [UUID: RestaurantTablePlacement] {
        var stored = layoutData
#if DEBUG && targetEnvironment(simulator)
        if let diagnosticLayout { stored = diagnosticLayout }
#endif
        let configuration = (try? RestaurantFloorLayout(stored: stored)) ?? RestaurantFloorLayout()
        return configuration.resolved(tables: orderedTables)
    }

#if DEBUG && targetEnvironment(simulator)
    private func sampleLayout(table: DiningTable) throws -> Data {
        var layout = RestaurantFloorLayout()
        let tables = orderedTables
        try layout.place(.init(slot: 8, shape: .rectangle), tableID: table.id, tables: tables)
        if let other = tables.first(where: { $0.label == "Table 6" }) {
            try layout.place(.init(slot: 5, shape: .rectangle, rotation: 1), tableID: other.id, tables: tables)
        }
        return try layout.encoded()
    }
#endif

    private func savePlacement(_ placement: RestaurantTablePlacement, tableID: UUID) throws {
        try service.authorize()
        guard service.admin, orderedTables.contains(where: { $0.id == tableID && $0.establishmentID == service.shop.id })
        else { throw RestaurantFault.access }
        var configuration = try RestaurantFloorLayout(stored: layoutData)
        try configuration.place(placement, tableID: tableID, tables: orderedTables)
        layoutData = try configuration.encoded()
    }

    @ViewBuilder private var plan: some View {
        let ordersByID = Dictionary(grouping: orders, by: \.id)
        let ordersWithLines = Set(lines.map(\.orderID))
        let states = Dictionary(uniqueKeysWithValues: tables.map { table in
            let hasLines = table.activeSessionID.map { ordersWithLines.contains($0) } ?? false
            return (table.id, RestaurantFloorState(table: table, hasOrderLines: hasLines))
        })
        if tables.isEmpty {
            ContentUnavailableView("Aucune table", systemImage: "table.furniture",
                description: Text("Ajoutez une table depuis la configuration du restaurant."))
        } else {
            filters(states)
            floorGrid(states)
            .padding(8)
            .background(COVITheme.champagne.opacity(0.30), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(COVITheme.navy.opacity(0.25))
                    .allowsHitTesting(false)
            }
            if let table = tables.first(where: { $0.id == selectedID }), let state = states[table.id] {
                let order = table.activeSessionID.flatMap { ordersByID[$0]?.first }
                selection(table, state: state, order: order)
                    .id("restaurant-table-summary")
            }
        }
    }

    private func floorGrid(_ states: [UUID: RestaurantFloorState]) -> some View {
        let positions = resolvedLayout
        let occupants = Dictionary(uniqueKeysWithValues: tables.compactMap { table in
            positions[table.id].map { ($0.slot, table) }
        })
        let slots = textSize.isAccessibilitySize
            ? occupants.keys.sorted() : Array(0..<(occupants.keys.max().map { $0 + 1 } ?? 0))
        let columns = textSize.isAccessibilitySize ? 1 : RestaurantFloorLayout.columns
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(slots, id: \.self) { slot in
                if let table = occupants[slot], let state = states[table.id], let placement = positions[table.id] {
                    floorTable(table, state: state, placement: placement)
                } else {
                    Color.clear.frame(height: 96).accessibilityHidden(true)
                }
            }
        }
    }

    private func filters(_ states: [UUID: RestaurantFloorState]) -> some View {
        let counts = Dictionary(grouping: states.values, by: { $0 }).mapValues(\.count)
        let columns = textSize.isAccessibilitySize ? 1 : sizeClass == .regular ? 4 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(RestaurantFloorState.allCases, id: \.self) { state in
                let selected = highlightedState == state
                Button { highlightedState = selected ? nil : state } label: {
                    HStack(spacing: 5) {
                        Circle().fill(selected ? .white : state.outline).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("\(state.rawValue) (\(counts[state] ?? 0))")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selected ? .white : COVITheme.navy)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 4)
                    .background(selected ? COVITheme.navy : .white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Met en évidence les tables dans cet état")
            }
        }
    }

    private func floorTable(_ table: DiningTable, state: RestaurantFloorState,
                            placement: RestaurantTablePlacement) -> some View {
        let selected = selectedID == table.id
        let emphasized = highlightedState == nil || highlightedState == state || selected
        return Button {
            selectedID = selected ? nil : table.id
            HapticService.tap()
        } label: {
            VStack(spacing: 2) {
                GeometryReader { proxy in
                    let turned = !placement.rotation.isMultiple(of: 2)
                    let size = turned ? CGSize(width: proxy.size.height, height: proxy.size.width) : proxy.size
                    let drawing = FloorTableDrawing(shape: placement.shape, capacity: table.capacity, size: size)
                    ZStack {
                        tableDrawing(drawing, state: state, selected: selected)
                            .frame(width: size.width, height: size.height)
                            .rotationEffect(.degrees(Double(placement.rotation) * 90))
                        if !textSize.isAccessibilitySize {
                            VStack(spacing: 2) {
                                Text(table.label)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1).minimumScaleFactor(0.66)
                                Label("\(table.capacity)", systemImage: "person")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(COVITheme.navy)
                            .padding(.horizontal, 3)
                            .frame(width: turned ? drawing.surface.height : drawing.surface.width)
                        }
                    }
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .frame(height: textSize.isAccessibilitySize ? 130 : 96)
                if textSize.isAccessibilitySize {
                    Text("\(table.label) · \(table.capacity) places")
                        .font(.headline)
                    Text(state.rawValue).font(.subheadline)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .opacity(emphasized ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(table.label), \(table.capacity) places, \(state.rawValue)")
        .accessibilityHint("Affiche le résumé de la table")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tableDrawing(_ drawing: FloorTableDrawing, state: RestaurantFloorState, selected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(drawing.chairCenters.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: drawing.chairSide * 0.32)
                    .fill(state.outline.opacity(0.65))
                    .frame(width: drawing.chairSide, height: drawing.chairSide)
                    .position(drawing.chairCenters[index])
            }
            RoundedRectangle(cornerRadius: drawing.cornerRadius)
                .fill(state.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: drawing.cornerRadius)
                        .strokeBorder(selected ? COVITheme.navy : state.outline.opacity(0.55),
                                      lineWidth: selected ? 2.5 : 1)
                }
                .frame(width: drawing.surface.width, height: drawing.surface.height)
                .position(x: drawing.surface.midX, y: drawing.surface.midY)
        }
    }

    private func selection(_ table: DiningTable, state: RestaurantFloorState, order: CommerceOrder?) -> some View {
        COVICard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(table.label).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        Label("Capacité : \(table.capacity) places", systemImage: "person")
                            .font(.subheadline)
                    }
                    Spacer(minLength: 6)
                    Button { selectedID = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fermer le résumé de la table")
                }
                COVIBadge(title: state.rawValue, tint: state.tint)
                if let order {
                    let amount = RestaurantBill.remaining(order, payments: payments)
                    LabeledContent(state == .checkout ? "Reste dû" : "Commande en cours",
                        value: amount.map { COVIMoney.text($0, currency: service.shop.currencyCode) } ?? "À vérifier")
                        .font(.subheadline)
                }
                if service.admin {
                    Button { editingTable = table } label: {
                        Label("Déplacer ou orienter", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    detail(table)
                } label: {
                    Label("Détails de la table", systemImage: "arrow.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(COVITheme.navy, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(COVITheme.navy)
        }
    }
}
