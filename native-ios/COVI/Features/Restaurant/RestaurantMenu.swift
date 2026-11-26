import SwiftUI
import SwiftData

struct RestaurantComposer: View {
    let menu: [CatalogItem]
    let table: DiningTable
    let order: CommerceOrder
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.modelContext) private var context
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
    #endif
    @State private var category = MenuGroup.food
    @State private var search = ""
    @State private var basket: [UUID:Int] = [:]
    @State private var message = ""
    @State private var sent = false
    var total: Int64 {
        menu.reduce(Int64(0)) { partial, item in
            let (line, overflow) = item.priceMinor.multipliedReportingOverflow(by: Int64(basket[item.id] ?? 0))
            let (next, exceeds) = partial.addingReportingOverflow(overflow ? Int64.max : line)
            return exceeds ? Int64.max : next
        }
    }
    private var categoryItems: [CatalogItem] {
        menu.filter { $0.menuCategory == category.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 9) {
                        ForEach(MenuGroup.allCases, id: \.self) { option in
                            Button { category = option } label: {
                                Text("\(option.rawValue) (\(menu.filter { $0.menuCategory == option.rawValue }.count))")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(category == option ? .white : COVITheme.navy)
                                    .background(category == option ? COVITheme.navy : .white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(category == option ? .isSelected : [])
                        }
                    }
                    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    let visibleItems = categoryItems.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
                    if visibleItems.isEmpty {
                        if query.isEmpty {
                            ContentUnavailableView("Aucun article disponible", systemImage: "fork.knife",
                                description: Text("Un responsable peut compléter la carte depuis Configurer."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    } else {
                        COVICard {
                            VStack(spacing: 12) {
                                ForEach(visibleItems) { item in
                                    if item.id != visibleItems.first?.id { Divider() }
                                    HStack(spacing: 10) {
                                        Image(systemName: category == .food ? "fork.knife" : "cup.and.saucer")
                                            .font(.title3)
                                            .frame(width: 44, height: 52)
                                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 12))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title).font(.headline)
                                            if item.soldOut {
                                                COVIBadge(title: "Épuisé", tint: COVITheme.dangerTint, foreground: .red)
                                            }
                                            Text(COVIMoney.text(item.priceMinor, currency: service.shop.currencyCode))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        Spacer(minLength: 0)
                                        HStack(spacing: 0) {
                                            let count = basket[item.id] ?? 0
                                            Button { basket[item.id] = count > 1 ? count - 1 : nil } label: {
                                                Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
                                            }
                                            .accessibilityLabel("Retirer une unité de \(item.title)")
                                            .disabled(count == 0)
                                            Text("\(count)").monospacedDigit().frame(minWidth: 14)
                                                .accessibilityLabel("Quantité : \(count)")
                                            Button { basket[item.id] = min(999, count + 1) } label: {
                                                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                                            }
                                            .accessibilityLabel("Ajouter une unité de \(item.title)")
                                            .disabled(item.soldOut || count >= 999)
                                        }
                                        .buttonStyle(.borderless)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(COVITheme.navy.opacity(0.28), lineWidth: 1)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .foregroundStyle(COVITheme.navy)
                                }
                            }
                        }
                    }
                    if !message.isEmpty { Text(message).foregroundStyle(.red) }
                }
                .padding(18)
            }
            .background(COVIBackdrop())
            .safeAreaInset(edge: .bottom) {
                COVIButton("Envoyer en cuisine (\(basket.values.reduce(0, +)) articles · \(COVIMoney.text(total, currency: service.shop.currencyCode)))") {
                    guard !sent else { return }
                    do {
                        try service.send(basket, menu: menu, table: table, order: order)
                        sent = true
                        HapticService.confirm()
                        dismiss()
                    } catch { message = error.localizedDescription; HapticService.error() }
                }
                .disabled(sent || basket.isEmpty)
                .padding(18)
                .background(COVITheme.cream)
            }
            .navigationTitle("Commander · " + table.label)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Rechercher dans la carte")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard let diagnostics, diagnostics.scenario == .restaurantOrder,
                  let sample = diagnostics.restaurantSample,
                  sample.table.id == table.id, sample.order.id == order.id,
                  context.container === diagnostics.container else { return }
            basket = sample.draft
        }
        #endif
    }
}

@MainActor
struct RestaurantSetup: View {
    let service: RestaurantService
    let tables: [DiningTable]
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var seats = 2
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Nouvelle table") {
                    TextField("Nom de la table", text: $label)
                    Stepper("\(seats) places", value: $seats, in: 1...100)
                    Button("Créer la table") { change {
                        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !tables.contains(where: { $0.label.caseInsensitiveCompare(name) == .orderedSame }) else { throw RestaurantFault.invalid }
                        let table = DiningTable(establishmentID: service.shop.id, label: name, capacity: seats)
                        service.db.insert(table)
                        label = ""
                        return ("restaurant.table.created", table.id)
                    } }
                }
                Section("Tables configurées") {
                    if tables.isEmpty {
                        Text("Ajoutez une table pour commencer le service.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tables) { table in
                        NavigationLink("\(table.label) · \(table.capacity) places") {
                            RestaurantTableEditor(table: table, service: service)
                        }
                    }
                }
                Section {
                    NavigationLink("Gestion de la carte") {
                        RestaurantMenuManagement(service: service)
                    }
                }
                if !message.isEmpty { Text(message) }
            }.navigationTitle("Salle et carte").toolbar { Button("Fermer") { dismiss() } }
        }
    }
    func change(_ mutation: () throws -> (String, UUID)) {
        do {
            try service.authorize()
            guard service.admin else { throw RestaurantFault.access }
            let (kind, entityID) = try mutation()
            try BusinessOutbox.enqueue(kind: kind, establishmentID: service.shop.id,
                                       entityID: entityID, actorID: service.actor, in: service.db)
            try service.save()
            message = "Enregistré."
        } catch {
            service.db.rollback()
            message = error.localizedDescription
        }
    }
}

struct RestaurantMenuManagement: View {
    let service: RestaurantService
    @Query private var items: [CatalogItem]
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var category = MenuGroup.food
    @State private var search = ""
    @State private var adding = false
    @State private var error = ""

    init(service: RestaurantService) {
        self.service = service
        let shopID = service.shop.id
        _items = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == shopID }, sort: \.title)
    }

    var body: some View {
        let selected = items.filter { $0.menuCategory == category.rawValue }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = selected.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                categoryButtons
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Rechercher un plat ou une boisson", text: $search)
                        .submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(COVITheme.navy.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                if visible.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("Aucun article", systemImage: "fork.knife",
                            description: Text("Ajoutez un article dans cette catégorie."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    COVICard {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(visible) { item in
                                if item.id != visible.first?.id { Divider() }
                                itemRow(item)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
        }
        .background(COVIBackdrop())
        .navigationTitle("Gestion de la carte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: {
                    Label("Article", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(COVITheme.navy)
                .accessibilityLabel("Ajouter un article")
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                RestaurantMenuEditor(item: nil, service: service, category: category)
            }
        }
        .alert("Gestion de la carte", isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("OK") { error = "" }
        } message: {
            Text(error)
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .restaurantMenu {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var categoryButtons: some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(MenuGroup.allCases, id: \.self) { group in
                let selected = category == group
                let count = items.filter { $0.menuCategory == group.rawValue }.count
                Button { category = group } label: {
                    Text("\(group.rawValue) (\(count))")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? .white : COVITheme.navy)
                        .background(selected ? COVITheme.navy : .clear,
                                    in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func itemRow(_ item: CatalogItem) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            NavigationLink {
                RestaurantMenuEditor(item: item, service: service,
                    category: MenuGroup(rawValue: item.menuCategory ?? "") ?? category)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.menuCategory == MenuGroup.drinks.rawValue ? "cup.and.saucer" : "fork.knife")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.bold())
                        Text(COVIMoney.text(item.priceMinor, currency: service.shop.currencyCode))
                            .font(.caption)
                            .foregroundStyle(COVITheme.secondaryText)
                        if item.soldOut {
                            Text("Rupture")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(COVITheme.dangerTint, in: Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 48)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre la fiche pour la modifier")
            Toggle("Disponibilité de \(item.title)", isOn: Binding(
                get: { !item.soldOut },
                set: { available in
                    do { try service.setMenuAvailability(item, available: available) }
                    catch { self.error = error.localizedDescription }
                }))
                .labelsHidden()
                .tint(COVITheme.success)
        }
    }
}

private struct RestaurantMenuEditor: View {
    let item: CatalogItem?
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var price: String
    @State private var category: MenuGroup
    @State private var error = ""

    init(item: CatalogItem?, service: RestaurantService, category: MenuGroup) {
        self.item = item
        self.service = service
        _title = State(initialValue: item?.title ?? "")
        _price = State(initialValue: item.map { String($0.priceMinor) } ?? "")
        _category = State(initialValue: category)
    }

    var body: some View {
        Form {
            TextField("Nom de l’article", text: $title)
            TextField("Prix en " + service.shop.currencyCode, text: $price).keyboardType(.numberPad)
            Picker("Catégorie", selection: $category) {
                ForEach(MenuGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button(item == nil ? "Ajouter à la carte" : "Enregistrer") {
                do {
                    if let item {
                        try service.editMenu(item, title: title, price: Int64(price) ?? 0, category: category)
                    } else {
                        try service.createMenuItem(title: title, price: Int64(price) ?? 0, category: category)
                    }
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if item != nil {
                Text("Les commandes déjà envoyées conservent leur prix et leur libellé d’origine.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(item == nil ? "Nouvel article" : "Modifier l’article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }
}

private struct RestaurantTableEditor: View {
    let table: DiningTable
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var seats = 2
    @State private var error = ""

    var body: some View {
        Form {
            TextField("Nom de la table", text: $label)
            Stepper("\(seats) places", value: $seats, in: 1...100)
            Button("Enregistrer la table") {
                do { try service.editTable(table, label: label, capacity: seats); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            .disabled(table.isOccupied)
            if table.isOccupied {
                Text("Libérez la table après le règlement avant de modifier sa configuration.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Modifier la table")
        .onAppear { label = table.label; seats = table.capacity }
    }
}
