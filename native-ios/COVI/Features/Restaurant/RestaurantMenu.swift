import SwiftUI
import SwiftData

struct RestaurantComposer: View {
    let menu: [CatalogItem]
    let table: DiningTable
    let order: CommerceOrder
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    @State private var category = MenuGroup.food
    @State private var basket: [UUID:Int] = [:]
    @State private var message = ""
    @State private var sent = false
    var body: some View {
        NavigationStack {
            List {
                Picker("Catégorie", selection: $category) {
                    ForEach(MenuGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ForEach(menu.filter { $0.menuCategory == category.rawValue }) { item in
                    Stepper(onIncrement: {
                        if !item.soldOut { basket[item.id] = min(999, (basket[item.id] ?? 0) + 1) }
                    }, onDecrement: {
                        let n = basket[item.id] ?? 0
                        basket[item.id] = n > 1 ? n - 1 : nil
                    }) {
                        Text("\(basket[item.id] ?? 0) × \(item.title)")
                        Text(item.soldOut ? "Rupture" : "\(item.priceMinor) FCFA").font(.caption)
                    }.disabled(item.soldOut && basket[item.id] == nil)
                }
                let total = menu.reduce(Decimal.zero) { $0 + Decimal($1.priceMinor) * Decimal(basket[$1.id] ?? 0) }
                COVIButton("Envoyer en cuisine · \(total.formatted()) FCFA") {
                    guard !sent else { return }
                    do {
                        try service.send(basket, menu: menu, table: table, order: order)
                        sent = true
                        HapticService.confirm()
                        dismiss()
                    } catch { message = error.localizedDescription; HapticService.error() }
                }.disabled(sent || basket.isEmpty)
                if !message.isEmpty { Text(message) }
            }.navigationTitle("Commander · " + table.label)
            .toolbar { Button("Fermer") { dismiss() } }
        }
    }
}

@MainActor
struct RestaurantSetup: View {
    let service: RestaurantService
    let menu: [CatalogItem]
    let tables: [DiningTable]
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var seats = 2
    @State private var dish = ""
    @State private var price = ""
    @State private var category = MenuGroup.food
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
                Section("Carte du restaurant") {
                    TextField("Nom de l’article", text: $dish)
                    TextField("Prix en FCFA", text: $price).keyboardType(.numberPad)
                    Picker("Catégorie", selection: $category) {
                        ForEach(MenuGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Ajouter à la carte") { change {
                        let name = dish.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, let value = Int64(price), value > 0 else { throw RestaurantFault.invalid }
                        let item = CatalogItem(establishmentID: service.shop.id, title: name, priceMinor: value)
                        item.menuCategory = category.rawValue
                        service.db.insert(item)
                        dish = ""; price = ""
                        return ("restaurant.menu.created", item.id)
                    } }
                    ForEach(menu.filter { $0.menuCategory != nil }) { item in
                        Toggle(item.title + (item.soldOut ? " · Rupture" : ""), isOn: Binding(get: { !item.soldOut }, set: { available in
                            change {
                                item.soldOut = !available
                                item.updatedAt = .now
                                return ("restaurant.menu.availability-changed", item.id)
                            }
                        }))
                        NavigationLink("Modifier · " + item.title) {
                            RestaurantMenuEditor(item: item, service: service)
                        }
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

private struct RestaurantMenuEditor: View {
    let item: CatalogItem
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var price = ""
    @State private var category = MenuGroup.food
    @State private var error = ""

    var body: some View {
        Form {
            TextField("Nom de l’article", text: $title)
            TextField("Prix en FCFA", text: $price).keyboardType(.numberPad)
            Picker("Catégorie", selection: $category) {
                ForEach(MenuGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Enregistrer la carte") {
                do {
                    try service.editMenu(item, title: title, price: Int64(price) ?? 0, category: category)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Text("Les commandes déjà envoyées conservent leur prix et leur libellé d’origine.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Modifier le menu")
        .onAppear {
            title = item.title
            price = String(item.priceMinor)
            category = MenuGroup(rawValue: item.menuCategory ?? "") ?? .food
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
