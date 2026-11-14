import SwiftUI
import SwiftData

struct NewProduct: View {
    let shop: Establishment
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
                guard let price = Int64(price), price > 0, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Nom et prix positif requis."; return }
                context.insert(CatalogItem(establishmentID: shop.id, title: title, priceMinor: price))
                do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
            }
            Text(error)
        }.navigationTitle("Nouvel article")
    }
}

struct ProductDetail: View {
    let item: CatalogItem
    let actor: UUID
    @Environment(\.modelContext) private var context
    @Query private var logs: [StockMovement]
    @State private var units = ""
    @State private var reason = ""
    @State private var operation = "Entrée"
    @State private var message = ""
    init(item: CatalogItem, actor: UUID) {
        self.item = item; self.actor = actor
        let id = item.id
        _logs = Query(filter: #Predicate<StockMovement> { $0.itemID == id }, sort: \.createdAt, order: .reverse)
    }
    var body: some View {
        List {
            Section(item.title) {
                Text("\(item.priceMinor) FCFA")
                LabeledContent("Stock · réservé", value: "\(item.stockOnHand) · \(item.stockReserved)")
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
                    context.insert(StockMovement(establishmentID: item.establishmentID, itemID: item.id, delta: delta, reason: operation + " · " + reason, actorID: actor))
                    item.stockOnHand = next; item.updatedAt = .now
                    do { try context.save(); units = ""; reason = ""; message = "Stock ajusté." }
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
                    context.insert(Bale(shop: shop.id, label: ref, cost: value))
                    do { try context.save(); cost = ""; label = "" } catch { context.rollback(); message = error.localizedDescription }
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
                            do { try context.save(); units = ""; message = "Pièces ajoutées." }
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
