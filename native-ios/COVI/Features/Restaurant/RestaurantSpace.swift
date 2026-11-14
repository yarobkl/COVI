import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

struct RestaurantSpace: View {
    let shop: Establishment
    let tab: BusinessTab
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    @Environment(\.modelContext) private var db
    @Query private var tables: [DiningTable]
    @Query private var orders: [CommerceOrder]
    @Query private var menu: [CatalogItem]
    @Query(sort: \OrderLine.sentAt) private var lines: [OrderLine]
    @State private var filter = "Toutes"
    @State private var phase = Prep.cooking
    @State private var setup = false
    @State private var message = ""
    init(shop: Establishment, tab: BusinessTab, actor: UUID, role: StaffRole, pin: PINManager) {
        self.shop = shop; self.tab = tab; self.actor = actor; self.role = role; self.pin = pin
        let id = shop.id
        _tables = Query(filter: #Predicate<DiningTable> { $0.establishmentID == id }, sort: \.label)
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id })
        _menu = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == id }, sort: \.title)
    }
    var service: RestaurantService { RestaurantService(shop: shop, actor: actor, role: role, pin: pin, db: db) }
    func state(_ t: DiningTable) -> String { t.billRequested ? "Addition demandée" : t.isOccupied ? "Occupée" : "Libre" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if tab == .kitchen {
                    Picker("Préparation", selection: $phase) {
                        ForEach(Prep.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    ForEach(tables) { t in
                        if let order = orders.first(where: { $0.id == t.activeSessionID }) {
                            ForEach(lines.filter { $0.orderID == order.id && $0.preparation == phase.rawValue }) { line in
                                COVICard { VStack(alignment: .leading, spacing: 8) {
                                    Text(t.label).font(.caption)
                                    Text("\(line.quantity) × \(line.dishName ?? "Article")").font(.headline)
                                    if let sent = line.sentAt { Text(sent, style: .time) }
                                    if phase == .cooking || phase == .ready {
                                        Button(phase == .cooking ? "Marquer prêt" : "Marquer servi") {
                                            perform { try service.advance(line, from: phase, table: t, order: order) }
                                        }
                                    }
                                } }
                            }
                        }
                    }
                } else {
                    Picker("État", selection: $filter) {
                        ForEach(["Toutes","Libre","Occupée","Addition demandée"], id: \.self) { Text($0) }
                    }.pickerStyle(.menu)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))]) {
                        ForEach(tables.filter { filter == "Toutes" || state($0) == filter }) { t in
                            NavigationLink {
                                RestaurantTable(table: t, order: orders.first { $0.id == t.activeSessionID }, menu: menu,
                                                lines: lines.filter { $0.orderID == t.activeSessionID }, service: service)
                            } label: {
                                COVICard { VStack(alignment: .leading, spacing: 8) {
                                    Label(t.label, systemImage: "table.furniture")
                                    Text("\(t.capacity) places").font(.caption)
                                    Text(state(t)).foregroundStyle(t.billRequested ? Color.orange : t.isOccupied ? COVITheme.navy : .green)
                                } }
                            }
                        }
                    }
                    if tables.isEmpty { Text("Aucune table configurée.") }
                }
            }.padding()
        }.background(COVITheme.cream).navigationTitle(tab == .kitchen ? "Cuisine" : tab.title)
        .toolbar { if service.admin && tab == .tables { Button("Configurer") { setup = true } } }
        .sheet(isPresented: $setup) { RestaurantSetup(service: service, menu: menu, tables: tables) }
        .alert("Restaurant", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("OK") {} } message: { Text(message) }
    }
    func perform(_ work: () throws -> Void) {
        do { try work(); HapticService.confirm() } catch { message = error.localizedDescription; HapticService.error() }
    }
}

struct RestaurantTable: View {
    let table: DiningTable
    let order: CommerceOrder?
    let menu: [CatalogItem]
    let lines: [OrderLine]
    let service: RestaurantService
    @State private var ordering = false
    @State private var closing = false
    @State private var qr = false
    @State private var message = ""
    var body: some View {
        List {
            Button("Code QR de la table") { qr = true }
            if let order {
                Section("Détail de la session") {
                    ForEach(lines) { line in
                        VStack(alignment: .leading) {
                            Text("\(line.quantity) × \(line.dishName ?? "Article")")
                            Text("\(line.unitPriceMinor) FCFA / unité · \(line.preparation ?? "")").font(.caption)
                            if line.preparation == Prep.ready.rawValue {
                                Button("Marquer servi") { run { try service.advance(line, from: .ready, table: table, order: order) } }
                            }
                        }
                    }
                }
                LabeledContent("Addition", value: "\(order.totalMinor) FCFA")
                if table.billRequested {
                    Button("Confirmer le règlement et libérer") { closing = true }
                } else {
                    Button("Ajouter à la commande") { ordering = true }
                    Button("Demander l’addition") { run { try service.finish(table, order: order, paid: false) } }
                }
            } else if !table.isOccupied {
                Button("Ouvrir une session") { run { try service.open(table) } }
            } else { Text("Session à réconcilier.") }
            if !message.isEmpty { Text(message) }
        }.navigationTitle(table.label)
        .confirmationDialog("Le règlement externe a-t-il été reçu ?", isPresented: $closing) {
            Button("Règlement confirmé") { if let order { run { try service.finish(table, order: order, paid: true) } } }
        }
        .sheet(isPresented: $ordering) { if let order { RestaurantComposer(menu: menu, table: table, order: order, service: service) } }
        .sheet(isPresented: $qr) {
            VStack {
                Text(table.label).font(.title)
                let filter = CIFilter.qrCodeGenerator()
                let payload = "covi:table/\(table.establishmentID.uuidString)/\(table.id.uuidString)"
                if let cg = Self.code(filter, payload) {
                    Image(decorative: cg, scale: 1).interpolation(.none).resizable().scaledToFit().padding(24).background(.white)
                }
            }.padding().presentationDetents([.medium])
        }
    }
    static func code(_ filter: CIFilter & CIQRCodeGenerator, _ payload: String) -> CGImage? {
        filter.message = Data(payload.utf8)
        guard let image = filter.outputImage else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
    func run(_ work: () throws -> Void) {
        do { try work(); message = ""; HapticService.confirm() } catch { message = error.localizedDescription; HapticService.error() }
    }
}
