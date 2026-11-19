import SwiftUI
import SwiftData

@MainActor enum BoutiqueInventoryService {
    enum Fault: LocalizedError {
        case invalid, duplicate, wrongShop
        var errorDescription: String? {
            switch self {
            case .invalid: "Saisissez un nom et un prix FCFA strictement positif."
            case .duplicate: "Un article portant ce nom existe déjà dans cette boutique."
            case .wrongShop: "Cet article n'appartient pas à cette boutique."
            }
        }
    }

    private static func validated(_ name: String, _ price: Int64, shopID: UUID,
                                  excluding: UUID?, context: ModelContext) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, price > 0 else { throw Fault.invalid }
        let items = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
            $0.establishmentID == shopID && !$0.isService
        }))
        guard !items.contains(where: {
            $0.id != excluding && $0.title.caseInsensitiveCompare(cleaned) == .orderedSame
        }) else { throw Fault.duplicate }
        return cleaned
    }

    @discardableResult
    static func create(shop: Establishment, name: String, price: Int64,
                       actor: UUID, context: ModelContext) throws -> CatalogItem {
        guard shop.kind == .boutique, !shop.archived else { throw Fault.wrongShop }
        let cleaned = try validated(name, price, shopID: shop.id, excluding: nil, context: context)
        let item = CatalogItem(establishmentID: shop.id, title: cleaned, priceMinor: price)
        context.insert(item)
        do {
            try BusinessOutbox.enqueue(kind: "boutique.product.created", establishmentID: shop.id,
                entityID: item.id, actorID: actor, in: context)
            try context.save()
            return item
        } catch { context.rollback(); throw error }
    }

    static func edit(_ item: CatalogItem, in shop: Establishment, name: String, price: Int64,
                     actor: UUID, context: ModelContext) throws {
        guard shop.kind == .boutique, !shop.archived,
              item.establishmentID == shop.id, !item.isService else { throw Fault.wrongShop }
        let cleaned = try validated(name, price, shopID: shop.id, excluding: item.id, context: context)
        guard cleaned != item.title || price != item.priceMinor else { return }
        item.title = cleaned
        item.priceMinor = price
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(kind: "boutique.product.edited", establishmentID: shop.id,
                entityID: item.id, actorID: actor, in: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

struct NewProduct: View {
    let shop: Establishment
    let actor: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var price = ""
    @State private var error = ""
    var body: some View {
        Form {
            TextField("Nom", text: $title)
            TextField("Prix en FCFA", text: $price).keyboardType(.numberPad)
            Button("Créer l’article") {
                do {
                    try BoutiqueInventoryService.create(shop: shop, name: title,
                        price: Int64(price) ?? 0, actor: actor, context: context)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
            Text(error)
        }.navigationTitle("Nouvel article")
    }
}

struct ProductDetail: View {
    let shop: Establishment
    let item: CatalogItem
    let actor: UUID
    @Environment(\.modelContext) private var context
    @Query private var logs: [StockMovement]
    @State private var units = ""
    @State private var reason = ""
    @State private var operation = "Entrée"
    @State private var message = ""
    @State private var editedName = ""
    @State private var editedPrice = ""
    init(shop: Establishment, item: CatalogItem, actor: UUID) {
        self.shop = shop; self.item = item; self.actor = actor
        let id = item.id
        _logs = Query(filter: #Predicate<StockMovement> { $0.itemID == id }, sort: \.createdAt, order: .reverse)
    }
    var body: some View {
        List {
            Section(item.title) {
                Text("\(item.priceMinor) FCFA")
                LabeledContent("Stock · réservé", value: "\(item.stockOnHand) · \(item.stockReserved)")
            }
            Section("Modifier l’article") {
                TextField("Nom de l’article", text: $editedName)
                TextField("Prix FCFA", text: $editedPrice).keyboardType(.numberPad)
                Button("Enregistrer les modifications") {
                    do {
                        try BoutiqueInventoryService.edit(item, in: shop, name: editedName,
                            price: Int64(editedPrice) ?? 0, actor: actor, context: context)
                        message = "Fiche mise à jour. Les anciens reçus restent inchangés."
                    } catch { message = error.localizedDescription }
                }
            }
            Section("Ajustement rapide du stock") {
                Picker("Type", selection: $operation) { ForEach(["Entrée", "Perte", "Inventaire", "Retour"], id: \.self) { Text($0) } }
                TextField(operation == "Inventaire" ? "Quantité comptée" : "Quantité", text: $units).keyboardType(.numberPad)
                TextField("Motif obligatoire", text: $reason)
                Button("Enregistrer l’ajustement") {
                    guard let count = Int(units), count >= 0, item.stockOnHand >= 0,
                          !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "Vérifiez quantité et motif."; return }
                    let delta = operation == "Inventaire" ? count - item.stockOnHand : (operation == "Perte" ? -count : count)
                    let (next, overflow) = item.stockOnHand.addingReportingOverflow(delta)
                    guard !overflow, delta != 0, next >= max(0, item.stockReserved) else { message = "Ajustement incompatible avec le disponible."; return }
                    let movement = StockMovement(establishmentID: item.establishmentID, itemID: item.id,
                                                 delta: delta, reason: operation + " · " + reason, actorID: actor)
                    context.insert(movement)
                    item.stockOnHand = next; item.updatedAt = .now
                    do {
                        try BusinessOutbox.enqueue(kind: "boutique.stock.adjusted",
                            establishmentID: item.establishmentID, entityID: item.id,
                            actorID: actor, relatedIDs: [movement.id], in: context)
                        try context.save(); units = ""; reason = ""; message = "Stock ajusté."
                    }
                    catch { context.rollback(); message = error.localizedDescription }
                }
                Text(message)
            }
            Section("Historique des mouvements") {
                ForEach(logs) { log in
                    VStack(alignment: .leading) {
                        Text("\(log.delta > 0 ? "+" : "")\(log.delta) · \(log.reason)")
                        Text(log.createdAt.formatted() + " · " + log.actorID.uuidString.prefix(8)).font(.caption)
                    }
                }
            }
        }.navigationTitle("Fiche produit").scrollContentBackground(.hidden).background(COVITheme.cream)
            .onAppear { editedName = item.title; editedPrice = String(item.priceMinor) }
    }
}

struct BaleList: View {
    let shop: Establishment
    let actor: UUID
    let goods: [CatalogItem]
    @Environment(\.modelContext) private var context
    @Query private var bales: [Bale]
    @Query private var movements: [StockMovement]
    @State private var label = ""
    @State private var cost = ""
    @State private var picked: UUID?
    @State private var units = ""
    @State private var message = ""
    var body: some View {
        List {
            Section("Nouvelle balle") {
                TextField("Référence du lot", text: $label)
                TextField("Coût du lot en FCFA", text: $cost).keyboardType(.numberPad)
                Button("Réceptionner la balle") {
                    let ref = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !ref.isEmpty, let value = Int64(cost), value >= 0,
                          !bales.contains(where: { $0.shop == shop.id && $0.label.caseInsensitiveCompare(ref) == .orderedSame })
                    else { message = "Vérifiez la référence et le coût."; return }
                    let bale = Bale(shop: shop.id, label: ref, cost: value)
                    context.insert(bale)
                    do {
                        try BusinessOutbox.enqueue(kind: "boutique.bale.received",
                            establishmentID: shop.id, entityID: bale.id, actorID: actor, in: context)
                        try context.save(); cost = ""; label = ""
                    } catch { context.rollback(); message = error.localizedDescription }
                }
            }
            ForEach(bales.filter { $0.shop == shop.id }.sorted { $0.received > $1.received }) { bale in
                NavigationLink(bale.label) {
                    Form {
                        LabeledContent("Coût du lot", value: "\(bale.cost) FCFA")
                        Picker("Article découvert", selection: $picked) {
                            Text("Choisir").tag(nil as UUID?)
                            ForEach(goods) { Text($0.title).tag(Optional($0.id)) }
                        }
                        TextField("Quantité découverte", text: $units).keyboardType(.numberPad)
                        Button("Ajouter les pièces au stock") {
                            guard let item = goods.first(where: { $0.id == picked && $0.establishmentID == shop.id }),
                                  let count = Int(units), count > 0 else { message = "Choisissez un article et une quantité."; return }
                            let (next, overflow) = item.stockOnHand.addingReportingOverflow(count)
                            guard !overflow else { message = "Quantité trop élevée."; return }
                            let log = StockMovement(establishmentID: shop.id, itemID: item.id, delta: count, reason: "Arrivage · " + bale.label, actorID: actor)
                            log.baleID = bale.id; context.insert(log)
                            item.stockOnHand = next; item.updatedAt = .now
                            do {
                                try BusinessOutbox.enqueue(kind: "boutique.bale.stock-added",
                                    establishmentID: shop.id, entityID: item.id,
                                    actorID: actor, relatedIDs: [bale.id, log.id], in: context)
                                try context.save(); units = ""; message = "Pièces ajoutées."
                            }
                            catch { context.rollback(); message = error.localizedDescription }
                        }
                        Section("Pièces découvertes") {
                            ForEach(movements.filter { $0.baleID == bale.id }) { log in
                                Text("\(goods.first { $0.id == log.itemID }?.title ?? "Article") · +\(log.delta)")
                            }
                        }
                        Text(message)
                    }.navigationTitle(bale.label)
                }
            }
            Text(message)
        }.navigationTitle("Arrivages")
    }
}
