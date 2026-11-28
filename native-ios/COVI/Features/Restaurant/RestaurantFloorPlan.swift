import SwiftUI

enum RestaurantFloorState: String, CaseIterable {
    case available = "Disponible"
    case occupied = "Occupée"
    case serving = "En service"
    case checkout = "À encaisser"
    case paidOccupied = "Réglée · occupée"

    init(table: DiningTable, hasOrderLines: Bool, settled: Bool = false) {
        if table.isOccupied && settled { self = .paidOccupied }
        else if table.billRequested { self = .checkout }
        else if !table.isOccupied { self = .available }
        else { self = hasOrderLines ? .serving : .occupied }
    }

    var tint: Color {
        switch self {
        case .available: COVITheme.successTint
        case .occupied: COVITheme.warningTint
        case .serving: Color(red: 0.85, green: 0.92, blue: 1)
        case .checkout: COVITheme.champagne
        case .paidOccupied: COVITheme.navy.opacity(0.12)
        }
    }

    var outline: Color {
        switch self {
        case .available: COVITheme.success
        case .occupied: COVITheme.warning
        case .serving: COVITheme.blue
        case .checkout, .paidOccupied: COVITheme.navy
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

enum RestaurantFloorZoom {
    static let limits: ClosedRange<CGFloat> = 1...2.5
    static let step: CGFloat = 0.25

    static func bounded(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return limits.lowerBound }
        return min(limits.upperBound, max(limits.lowerBound, scale))
    }
}

struct RestaurantFloorPlan<Detail: View>: View {
    private struct TableSession: Identifiable {
        let table: DiningTable
        let order: CommerceOrder
        var id: UUID { order.id }
    }

    private enum OrderSheet: Identifiable {
        case guests(DiningTable)
        case composer(TableSession)

        var id: UUID {
            switch self {
            case .guests(let table): table.id
            case .composer(let session): session.id
            }
        }
    }

    let tables: [DiningTable]
    let orders: [CommerceOrder]
    let lines: [OrderLine]
    let payments: [PaymentRecord]
    let menu: [CatalogItem]
    let service: RestaurantService
    private let detail: (DiningTable) -> Detail
    @AppStorage private var layoutData: Data
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var tableNameLineHeight: CGFloat = 16
    @State private var selectedID: UUID?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var roomID: UUID?
    @State private var renamingRoom: RestaurantFloorRoom?
    @State private var showingRoomEditor = false
    @State private var highlightedState: RestaurantFloorState?
    @State private var detailTableID: UUID?
    @State private var editingTable: DiningTable?
    @State private var checkout: TableSession?
    @State private var orderSheet: OrderSheet?
    @State private var nextOrder: TableSession?
    @State private var actionError = ""
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    @State private var diagnosticLayout: Data?
#endif

    init(tables: [DiningTable], orders: [CommerceOrder], lines: [OrderLine], payments: [PaymentRecord],
         menu: [CatalogItem], service: RestaurantService, @ViewBuilder detail: @escaping (DiningTable) -> Detail) {
        self.tables = tables
        self.orders = orders
        self.lines = lines
        self.payments = payments
        self.menu = menu
        self.service = service
        self.detail = detail
        _layoutData = AppStorage(wrappedValue: Data(), "covi.floor-plan.v1." + service.shop.id.uuidString)
    }

    private var orderedTables: [DiningTable] {
        tables.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private var compactOverview: Bool {
        sizeClass == .compact && textSize <= .large
    }

    var body: some View {
        let current = configuration
        let room = current.spaces.first { $0.id == roomID }
        VStack(spacing: 0) {
            roomBar(active: room, spaces: current.spaces)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: compactOverview ? 10 : 16) {
                        plan(configuration: current, room: room)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, compactOverview ? 8 : 18)
                }
                .onChange(of: selectedID) { _, id in
                    guard id != nil else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                        scroll.scrollTo("restaurant-table-summary", anchor: textSize.isAccessibilitySize ? .top : .bottom)
                    }
                }
#if DEBUG && targetEnvironment(simulator)
                .task {
                    if let diagnostics, diagnostics.scenario.isFloorPlan,
                       let sample = tables.first(where: { $0.label == diagnostics.scenario.floorSampleLabel }) {
                        if let layoutTable = tables.first(where: { $0.label == "Table 10" }),
                           let staged = try? sampleLayout(table: layoutTable, terrace: diagnostics.scenario == .restaurantFloorTerrace) {
                            diagnosticLayout = try? staged.encoded()
                            roomID = staged.spaces.first?.id
                        }
                        if diagnostics.scenario == .restaurantFloorZoom { zoom = 1.5 }
                        else { selectedID = sample.id }
                        if diagnostics.scenario == .restaurantFloorEdit { editingTable = sample }
                        else if diagnostics.scenario == .restaurantFloorOrderStart { presentOrder(sample) }
                        else if diagnostics.scenario == .restaurantFloorCheckoutSheet,
                                let order = orders.first(where: { $0.id == sample.activeSessionID }) {
                            presentCheckout(sample, order: order)
                        }
                        else { await diagnostics.signalAfterPresentation() }
                    }
                }
#endif
            }
        }
        .navigationDestination(item: $detailTableID) { id in
            if let table = tables.first(where: { $0.id == id }) {
                detail(table)
            }
        }
        .sheet(item: $editingTable) { table in
            let current = resolvedLayout
            if let placement = current[table.id] {
                RestaurantFloorEditor(table: table, placement: placement, spaces: configuration.spaces,
                                      otherPositions: Array(current.filter { $0.key != table.id }.values)) {
                    try savePlacement($0, tableID: table.id)
                }
            }
        }
        .sheet(item: $checkout) { target in
            RestaurantCheckout(table: target.table, order: target.order, service: service)
                .presentationDetents([.fraction(0.84), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $orderSheet, onDismiss: {
            if let nextOrder {
                self.nextOrder = nil
                orderSheet = .composer(nextOrder)
            }
        }) { sheet in
            switch sheet {
            case .guests(let table):
                RestaurantGuestEditor(table: table, existingCount: nil) { count in
                    let order = try service.open(table, guestCount: count)
                    nextOrder = TableSession(table: table, order: order)
                }
            case .composer(let target):
                RestaurantComposer(menu: menu, table: target.table, order: target.order, service: service)
            }
        }
        .sheet(isPresented: $showingRoomEditor) {
            RestaurantFloorRoomEditor(existing: renamingRoom) { name, kind in
                let added = try saveLayout { layout -> UUID? in
                    if let existing = renamingRoom {
                        try layout.renameRoom(existing.id, name: name)
                        return nil
                    }
                    return try layout.addRoom(name: name, kind: kind).id
                }
                if let added { selectRoom(added) }
            }
        }
        .alert("Salle", isPresented: Binding(get: { !actionError.isEmpty },
            set: { if !$0 { actionError = "" } })) {
            Button("OK") {}
        } message: {
            Text(actionError)
        }
    }

    private func presentCheckout(_ table: DiningTable, order: CommerceOrder) {
        do {
            guard try service.paymentBalance(table, order: order) > 0 else { throw RestaurantFault.invalid }
            checkout = TableSession(table: table, order: order)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func presentOrder(_ table: DiningTable) {
        do {
            try service.authorize()
            guard table.establishmentID == service.shop.id,
                  !table.isOccupied, table.activeSessionID == nil else { throw RestaurantFault.stale }
            orderSheet = .guests(table)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var configuration: RestaurantFloorLayout {
        var stored = layoutData
#if DEBUG && targetEnvironment(simulator)
        if let diagnosticLayout { stored = diagnosticLayout }
#endif
        return (try? RestaurantFloorLayout(stored: stored)) ?? RestaurantFloorLayout()
    }

    private var resolvedLayout: [UUID: RestaurantTablePlacement] {
        configuration.resolved(tables: orderedTables)
    }

#if DEBUG && targetEnvironment(simulator)
    private func sampleLayout(table: DiningTable, terrace: Bool) throws -> RestaurantFloorLayout {
        var layout = RestaurantFloorLayout()
        let tables = orderedTables
        try layout.place(.init(slot: 8, shape: .rectangle), tableID: table.id, tables: tables)
        if let other = tables.first(where: { $0.label == "Table 6" }) {
            try layout.place(.init(slot: 5, shape: .rectangle, rotation: 1), tableID: other.id, tables: tables)
        }
        if terrace {
            let outdoor = try layout.addRoom(name: "Terrasse", kind: .outdoor)
            try layout.place(.init(slot: 2, shape: .rectangle, roomID: outdoor.id), tableID: table.id, tables: tables)
            if let other = tables.first(where: { $0.label == "Table 2" }) {
                try layout.place(.init(slot: 0, shape: .oval, roomID: outdoor.id), tableID: other.id, tables: tables)
            }
        }
        return layout
    }
#endif

    private func savePlacement(_ placement: RestaurantTablePlacement, tableID: UUID) throws {
        try saveLayout { layout in
            guard orderedTables.contains(where: { $0.id == tableID && $0.establishmentID == service.shop.id })
            else { throw RestaurantFault.access }
            try layout.place(placement, tableID: tableID, tables: orderedTables)
        }
        if roomID != placement.roomID {
            roomID = placement.roomID
            zoom = 1
            highlightedState = nil
        }
    }

    private func saveLayout<Result>(_ update: (inout RestaurantFloorLayout) throws -> Result) throws -> Result {
        try service.authorize()
        guard service.admin else { throw RestaurantFault.access }
        var current = try RestaurantFloorLayout(stored: layoutData)
        let result = try update(&current)
        layoutData = try current.encoded()
        return result
    }

    private func selectRoom(_ id: UUID?) {
        roomID = id
        zoom = 1
        highlightedState = nil
        selectedID = nil
    }

    @ViewBuilder private func plan(configuration: RestaurantFloorLayout, room: RestaurantFloorRoom?) -> some View {
        let positions = configuration.resolved(tables: orderedTables)
        let displayed = tables.filter { positions[$0.id]?.roomID == room?.id }
        let ordersByID = Dictionary(grouping: orders, by: \.id)
        let ordersWithLines = Set(lines.map(\.orderID))
        let states = Dictionary(uniqueKeysWithValues: displayed.map { table in
            let hasLines = table.activeSessionID.map { ordersWithLines.contains($0) } ?? false
            let settled = table.activeSessionID.flatMap { ordersByID[$0]?.first?.state } == .completed
            return (table.id, RestaurantFloorState(table: table, hasOrderLines: hasLines, settled: settled))
        })
        if displayed.isEmpty {
            ContentUnavailableView("Aucune table dans cet espace", systemImage: "table.furniture",
                description: Text("Les nouvelles tables apparaissent en salle principale. Déplacez-les depuis leur résumé."))
        } else {
            filters(states)
            floorViewport(states, tables: displayed, positions: positions)
                .padding(8)
                .background(COVITheme.champagne.opacity(0.30), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(COVITheme.navy.opacity(0.25))
                        .allowsHitTesting(false)
                }
            if let table = displayed.first(where: { $0.id == selectedID }),
               let state = states[table.id], let placement = positions[table.id] {
                let order = table.activeSessionID.flatMap { ordersByID[$0]?.first }
                selection(table, placement: placement, state: state, order: order)
                    .id("restaurant-table-summary")
            }
        }
    }

    private func roomBar(active: RestaurantFloorRoom?, spaces: [RestaurantFloorRoom]) -> some View {
        HStack(spacing: 10) {
            Menu {
                Button(RestaurantFloorLayout.mainRoomName, systemImage: "door.left.hand.closed") { selectRoom(nil) }
                ForEach(spaces) { room in
                    Button(room.name, systemImage: room.kind.symbol) { selectRoom(room.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: active?.kind.symbol ?? "door.left.hand.closed")
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                    Text(active?.name ?? RestaurantFloorLayout.mainRoomName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down").font(.system(size: 13))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .padding(.vertical, textSize.isAccessibilitySize ? 6 : 0)
                .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityHint("Choisir une salle ou une terrasse")
            Spacer(minLength: 0)
            if !textSize.isAccessibilitySize {
                zoomMenu
            }
            if service.admin {
                Menu {
                    Button("Ajouter un espace", systemImage: "plus") {
                        renamingRoom = nil
                        showingRoomEditor = true
                    }
                    if let active {
                        Button("Renommer cet espace", systemImage: "pencil") {
                            renamingRoom = active
                            showingRoomEditor = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Gérer les espaces")
            }
        }
        .foregroundStyle(COVITheme.navy)
    }

    private var zoomMenu: some View {
        Menu {
            Button("Agrandir", systemImage: "plus.magnifyingglass") {
                zoom = RestaurantFloorZoom.bounded(zoom + RestaurantFloorZoom.step)
            }
            .disabled(zoom >= RestaurantFloorZoom.limits.upperBound)
            Button("Réduire", systemImage: "minus.magnifyingglass") {
                zoom = RestaurantFloorZoom.bounded(zoom - RestaurantFloorZoom.step)
            }
            .disabled(zoom <= RestaurantFloorZoom.limits.lowerBound)
            Button("Vue d’ensemble", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                zoom = 1
            }
            .disabled(zoom == 1)
        } label: {
            Label("\(Int((zoom * 100).rounded())) %", systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Zoom du plan")
        .accessibilityValue("\(Int((zoom * 100).rounded())) pour cent")
    }

    @ViewBuilder private func floorViewport(_ states: [UUID: RestaurantFloorState], tables: [DiningTable],
                                             positions: [UUID: RestaurantTablePlacement]) -> some View {
        if textSize.isAccessibilitySize {
            floorGrid(states, tables: tables, positions: positions, rowHeight: 130)
        } else {
            let last = tables.compactMap { positions[$0.id]?.slot }.max() ?? 0
            let rows = last / RestaurantFloorLayout.columns + 1
            let rowHeight: CGFloat = compactOverview && rows <= 3 ? 68 : 96
            let baseHeight = CGFloat(rows) * (rowHeight + 8) - 8
            let scale = RestaurantFloorZoom.bounded(zoom * pinchScale)
            GeometryReader { proxy in
                let width = proxy.size.width
                ScrollView([.horizontal, .vertical]) {
                    floorGrid(states, tables: tables, positions: positions, rowHeight: rowHeight)
                        .frame(width: width, height: baseHeight)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: width * scale, height: baseHeight * scale, alignment: .topLeading)
                }
                .scrollDisabled(scale == 1)
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinchScale) { value, scale, _ in scale = value.magnification }
                        .onEnded { value in zoom = RestaurantFloorZoom.bounded(zoom * value.magnification) }
                )
            }
            .frame(height: zoom == 1 ? baseHeight : min(baseHeight * zoom, 390))
        }
    }

    private func floorGrid(_ states: [UUID: RestaurantFloorState], tables: [DiningTable],
                           positions: [UUID: RestaurantTablePlacement], rowHeight: CGFloat) -> some View {
        let occupants = Dictionary(uniqueKeysWithValues: tables.compactMap { table in
            positions[table.id].map { ($0.slot, table) }
        })
        let slots = textSize.isAccessibilitySize
            ? occupants.keys.sorted() : Array(0..<(occupants.keys.max().map { $0 + 1 } ?? 0))
        let columns = textSize.isAccessibilitySize ? 1 : RestaurantFloorLayout.columns
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(slots, id: \.self) { slot in
                if let table = occupants[slot], let state = states[table.id], let placement = positions[table.id] {
                    floorTable(table, state: state, placement: placement, rowHeight: rowHeight)
                } else {
                    Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                }
            }
        }
    }

    private func filters(_ states: [UUID: RestaurantFloorState]) -> some View {
        let counts = Dictionary(grouping: states.values, by: { $0 }).mapValues(\.count)
        let filters = RestaurantFloorState.allCases.filter { $0 != .paidOccupied || counts[$0] != nil }
        let compactFilters = compactOverview && filters.count == 4
        let columns = textSize.isAccessibilitySize ? 1 : (compactFilters || sizeClass == .regular ? 4 : 2)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 6) {
            ForEach(filters, id: \.self) { state in
                filterButton(state, count: counts[state] ?? 0, compact: compactFilters)
            }
        }
    }

    private func filterButton(_ state: RestaurantFloorState, count: Int, compact: Bool) -> some View {
        let selected = highlightedState == state
        return Button { highlightedState = selected ? nil : state } label: {
            HStack(spacing: 4) {
                Circle().fill(selected ? .white : state.outline)
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                    .accessibilityHidden(true)
                Text("\(state.rawValue) (\(count))")
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? .white : COVITheme.navy)
            .padding(.horizontal, compact ? 2 : 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? COVITheme.navy : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Met en évidence les tables dans cet état")
    }

    private func floorTable(_ table: DiningTable, state: RestaurantFloorState,
                            placement: RestaurantTablePlacement, rowHeight: CGFloat) -> some View {
        let selected = selectedID == table.id
        let emphasized = highlightedState == nil || highlightedState == state || selected
        let turned = !placement.rotation.isMultiple(of: 2)
        let nameBelowDrawing = turned && !textSize.isAccessibilitySize
        let drawingHeight = rowHeight - (nameBelowDrawing ? tableNameLineHeight + 2 : 0)
        return Button {
            selectedID = selected ? nil : table.id
            HapticService.tap()
        } label: {
            VStack(spacing: 2) {
                GeometryReader { proxy in
                    let size = turned ? CGSize(width: proxy.size.height, height: proxy.size.width) : proxy.size
                    let drawing = FloorTableDrawing(shape: placement.shape, capacity: table.capacity, size: size)
                    ZStack {
                        tableDrawing(drawing, state: state, selected: selected)
                            .frame(width: size.width, height: size.height)
                            .rotationEffect(.degrees(Double(placement.rotation) * 90))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        if !textSize.isAccessibilitySize {
                            VStack(spacing: 2) {
                                if !nameBelowDrawing {
                                    floorTableName(table.label)
                                }
                                HStack(spacing: 2) {
                                    Image(systemName: "person")
                                    Text("\(table.capacity)")
                                }
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(COVITheme.navy)
                            .padding(.horizontal, nameBelowDrawing ? 0 : 3)
                            .frame(width: turned ? drawing.surface.height : drawing.surface.width)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                }
                .frame(height: drawingHeight)
                if nameBelowDrawing {
                    floorTableName(table.label)
                        .frame(maxWidth: .infinity, minHeight: tableNameLineHeight, maxHeight: tableNameLineHeight)
                        .accessibilityHidden(true)
                } else if textSize.isAccessibilitySize {
                    Text("\(table.label) · \(table.capacity) places")
                        .font(.headline)
                    Text(state.rawValue).font(.subheadline)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .opacity(emphasized ? 1 : 0.48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(table.label), \(table.capacity) places, \(state.rawValue)")
        .accessibilityHint("Affiche le résumé de la table")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func floorTableName(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.66)
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

    private func selection(_ table: DiningTable, placement: RestaurantTablePlacement,
                           state: RestaurantFloorState, order: CommerceOrder?) -> some View {
        let canStart = state == .available && table.activeSessionID == nil &&
            (service.admin || service.role == .waiter)
        let bill = order.flatMap { candidate -> CommerceOrder? in
            guard state == .checkout, candidate.state == .accepted,
                  let due = try? RestaurantBill.checkoutBalance(candidate,
                      lines: lines.filter { $0.orderID == candidate.id }, payments: payments),
                  due > 0 else { return nil }
            return candidate
        }
        let compactActions = compactOverview && (canStart || bill != nil)
        return COVICard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if textSize <= .large {
                        let size = CGSize(width: 58, height: 52)
                        let rotated = !placement.rotation.isMultiple(of: 2)
                        let drawingSize = rotated ? CGSize(width: size.height, height: size.width) : size
                        let drawing = FloorTableDrawing(shape: placement.shape, capacity: table.capacity, size: drawingSize)
                        tableDrawing(drawing, state: state, selected: true)
                            .frame(width: drawingSize.width, height: drawingSize.height)
                            .rotationEffect(.degrees(Double(placement.rotation) * 90))
                            .frame(width: size.width, height: size.height)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        selectionHeading(table, order: order)
                        COVIBadge(title: state.rawValue, tint: state.tint)
                    }
                }
                if let order {
                    let amount = RestaurantBill.remaining(order, payments: payments)
                    let paid = state == .paidOccupied
                    let title = paid ? "Addition réglée" : state == .checkout ? "Reste dû" : "Commande en cours"
                    let value = (paid ? order.totalMinor : amount).map {
                        COVIMoney.text($0, currency: service.shop.currencyCode)
                    } ?? "À vérifier"
                    Group {
                        if textSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                Text(value).fontWeight(.semibold)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            LabeledContent(title, value: value)
                        }
                    }
                        .font(.subheadline)
                }
                if !compactActions {
                    primaryAction(for: table, canStart: canStart, bill: bill, compact: false)
                }
                let actionLayout = textSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                actionLayout {
                    if compactActions {
                        primaryAction(for: table, canStart: canStart, bill: bill, compact: true)
                    }
                    if service.admin {
                        moveAction(for: table, compact: compactActions)
                    }
                    Menu {
                        Button("Détails de la table", systemImage: "table.furniture") {
                            detailTableID = table.id
                        }
                    } label: {
                        tableActionLabel("Plus", symbol: "ellipsis", compact: compactActions)
                    }
                    .accessibilityLabel("Plus d’actions pour \(table.label)")
                    .accessibilityIdentifier("restaurant-floor-table-more")
                }
            }
            .foregroundStyle(COVITheme.navy)
        }
    }

    @ViewBuilder private func primaryAction(for table: DiningTable, canStart: Bool,
                                            bill: CommerceOrder?, compact: Bool) -> some View {
        if canStart {
            COVIButton("Prendre une commande",
                       systemImage: compact || textSize.isAccessibilitySize ? nil : "plus.circle") {
                presentOrder(table)
            }
            .layoutPriority(1)
        } else if let bill {
            COVIButton("Encaisser", systemImage: textSize.isAccessibilitySize ? nil : "creditcard",
                       role: .secondary) {
                presentCheckout(table, order: bill)
            }
            .layoutPriority(1)
        }
    }

    @ViewBuilder private func moveAction(for table: DiningTable, compact: Bool) -> some View {
        let symbol = "arrow.up.and.down.and.arrow.left.and.right"
        if compact {
            Button { editingTable = table } label: {
                tableActionLabel("Déplacer", symbol: symbol, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Déplacer ou orienter")
        } else {
            COVIButton("Déplacer", systemImage: textSize.isAccessibilitySize ? nil : symbol,
                       role: .secondary) { editingTable = table }
                .accessibilityLabel("Déplacer ou orienter")
        }
    }

    private func tableActionLabel(_ title: LocalizedStringKey, symbol: String, compact: Bool) -> some View {
        Group {
            if compact {
                VStack(spacing: 4) {
                    Image(systemName: symbol).font(.subheadline)
                        .accessibilityHidden(true)
                    Text(title).font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 44)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Group {
                    if textSize.isAccessibilitySize {
                        Text(title)
                    } else {
                        Label(title, systemImage: symbol)
                    }
                }
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: COVITheme.Metrics.buttonHeight)
        .foregroundStyle(COVITheme.navy)
        .background(COVITheme.champagne.opacity(0.30),
                    in: RoundedRectangle(cornerRadius: COVITheme.Metrics.buttonRadius))
        .overlay {
            RoundedRectangle(cornerRadius: COVITheme.Metrics.buttonRadius)
                .strokeBorder(COVITheme.navy.opacity(0.35), lineWidth: 1.5)
        }
    }

    private func selectionHeading(_ table: DiningTable, order: CommerceOrder?) -> some View {
        let guests = order?.restaurantGuestCount ?? (table.isOccupied ? nil : 0)
        return VStack(alignment: .leading, spacing: 4) {
            Text(table.label)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 48)
            Group {
                if textSize.isAccessibilitySize {
                    Text("Capacité : \(table.capacity)")
                        .accessibilityLabel("Capacité : \(table.capacity) places")
                    if let guests {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Places occupées")
                            Text("\(guests) sur \(table.capacity)").fontWeight(.semibold)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("Convives non renseignés")
                    }
                } else {
                    Label("Capacité : \(table.capacity) places", systemImage: "person")
                    if let guests {
                        Label("Places occupées : \(guests) / \(table.capacity)", systemImage: "person.2")
                    } else {
                        Label("Convives non renseignés", systemImage: "person.2")
                    }
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, textSize.isAccessibilitySize ? 0 : 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button { selectedID = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer le résumé de la table")
        }
    }
}
