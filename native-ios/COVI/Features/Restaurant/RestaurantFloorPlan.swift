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
    private struct CheckoutTarget: Identifiable {
        let table: DiningTable
        let order: CommerceOrder
        var id: UUID { order.id }
    }

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
    @State private var zoom: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var roomID: UUID?
    @State private var renamingRoom: RestaurantFloorRoom?
    @State private var showingRoomEditor = false
    @State private var highlightedState: RestaurantFloorState?
    @State private var editingTable: DiningTable?
    @State private var checkout: CheckoutTarget?
    @State private var checkoutError = ""
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
        let current = configuration
        let room = current.spaces.first { $0.id == roomID }
        VStack(spacing: 0) {
            roomBar(active: room, spaces: current.spaces)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        plan(configuration: current, room: room)
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
        .alert("Encaissement", isPresented: Binding(get: { !checkoutError.isEmpty },
            set: { if !$0 { checkoutError = "" } })) {
            Button("OK") {}
        } message: {
            Text(checkoutError)
        }
    }

    private func presentCheckout(_ table: DiningTable, order: CommerceOrder) {
        do {
            guard try service.paymentBalance(table, order: order) > 0 else { throw RestaurantFault.invalid }
            checkout = CheckoutTarget(table: table, order: order)
        } catch {
            checkoutError = error.localizedDescription
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
            if let table = displayed.first(where: { $0.id == selectedID }), let state = states[table.id] {
                let order = table.activeSessionID.flatMap { ordersByID[$0]?.first }
                selection(table, state: state, order: order)
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
                    Label(active?.name ?? RestaurantFloorLayout.mainRoomName, systemImage: active?.kind.symbol ?? "door.left.hand.closed")
                    Image(systemName: "chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
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
                        .font(.title3)
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
            floorGrid(states, tables: tables, positions: positions)
        } else {
            let last = tables.compactMap { positions[$0.id]?.slot }.max() ?? 0
            let rows = last / RestaurantFloorLayout.columns + 1
            let baseHeight = CGFloat(rows) * 104 - 8
            let scale = RestaurantFloorZoom.bounded(zoom * pinchScale)
            GeometryReader { proxy in
                let width = proxy.size.width
                ScrollView([.horizontal, .vertical]) {
                    floorGrid(states, tables: tables, positions: positions)
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
                           positions: [UUID: RestaurantTablePlacement]) -> some View {
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
            ForEach(RestaurantFloorState.allCases.filter { $0 != .paidOccupied || counts[$0] != nil }, id: \.self) { state in
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
                        if let guests = order?.restaurantGuestCount ?? (table.isOccupied ? nil : 0) {
                            Label("Places occupées : \(guests) / \(table.capacity)", systemImage: "person.2")
                                .font(.subheadline)
                        } else {
                            Label("Convives non renseignés", systemImage: "person.2")
                                .font(.subheadline)
                        }
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
                    let paid = state == .paidOccupied
                    LabeledContent(paid ? "Addition réglée" : state == .checkout ? "Reste dû" : "Commande en cours",
                        value: (paid ? order.totalMinor : amount).map {
                            COVIMoney.text($0, currency: service.shop.currencyCode)
                        } ?? "À vérifier")
                        .font(.subheadline)
                }
                let actionLayout = textSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                actionLayout {
                    if service.admin {
                        COVIButton("Déplacer", systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                                   role: .secondary) { editingTable = table }
                            .accessibilityLabel("Déplacer ou orienter")
                    }
                    if let order, state == .checkout, order.state == .accepted,
                       let due = try? RestaurantBill.checkoutBalance(order,
                           lines: lines.filter { $0.orderID == order.id }, payments: payments), due > 0 {
                        COVIButton("Encaisser", systemImage: "creditcard", role: .secondary) {
                            presentCheckout(table, order: order)
                        }
                    }
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
