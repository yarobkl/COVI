import SwiftUI
import SwiftData
import UIKit

struct StockSnapshot {
    let articleCount: Int
    let suspendedCount: Int
    let availableUnits: Decimal
    let retailValue: Decimal
    let lowStock: [CatalogItem]
    let invalidItems: [CatalogItem]

    static func make(items: [CatalogItem], shopID: UUID) -> StockSnapshot {
        let catalog = items.filter { $0.establishmentID == shopID && !$0.isService }
        let inconsistent = catalog.filter {
            $0.stockOnHand < 0 || $0.stockReserved < 0 ||
            $0.stockReserved > $0.stockOnHand || $0.priceMinor < 0
        }
        let invalidIDs = Set(inconsistent.map(\.id))
        let valid = catalog.filter { !invalidIDs.contains($0.id) }
        let available = valid.reduce(Decimal.zero) {
            $0 + Decimal($1.stockOnHand - $1.stockReserved)
        }
        let value = valid.reduce(Decimal.zero) {
            $0 + Decimal($1.stockOnHand - $1.stockReserved) * Decimal($1.priceMinor)
        }
        return StockSnapshot(articleCount: catalog.count,
                             suspendedCount: catalog.filter(\.soldOut).count,
                             availableUnits: available, retailValue: value,
                             lowStock: valid.filter { !$0.soldOut && $0.stockOnHand - $0.stockReserved <= 2 }
                                 .sorted { $0.title < $1.title },
                             invalidItems: inconsistent.sorted { $0.title < $1.title })
    }
}

struct BoutiqueStockOverview: View {
    let shop: Establishment
    let goods: [CatalogItem]
    @State private var exporting = false
    @State private var exportError = ""

    var body: some View {
        let summary = StockSnapshot.make(items: goods, shopID: shop.id)
        List {
            Section("Inventaire disponible") {
                LabeledContent("Références", value: String(summary.articleCount))
                LabeledContent("Références en pause", value: String(summary.suspendedCount))
                LabeledContent("Unités disponibles", value: summary.availableUnits.formatted())
                LabeledContent("Valeur au prix de vente", value: "\(summary.retailValue.formatted()) \(shop.currencyCode)")
                Text("Les quantités comprennent les articles temporairement retirés de la vente. La valeur utilise les prix de vente : ce n'est ni le coût d'achat ni le bénéfice.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Stock faible · deux pièces ou moins") {
                if summary.lowStock.isEmpty { Text("Aucun article en alerte.").foregroundStyle(.secondary) }
                ForEach(summary.lowStock) { item in
                    LabeledContent(item.title,
                                   value: "\(item.stockOnHand - item.stockReserved) disponibles")
                }
            }
            if !summary.invalidItems.isEmpty {
                Section("Inventaire à vérifier") {
                    Text("Ces articles comportent une quantité réservée ou un prix incohérent. La valeur n'a pas été ajoutée au total.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(summary.invalidItems) { Text($0.title).foregroundStyle(.orange) }
                }
            }
            Section("Sauvegarde de l'inventaire") {
                Button("Exporter le stock CSV", systemImage: "square.and.arrow.up") { exporting = true }
                Text("Export de cet établissement uniquement. Les articles en pause et les réservations sont conservés dans le fichier.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !exportError.isEmpty { Text(exportError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("État des stocks")
        .scrollContentBackground(.hidden).background(COVITheme.cream)
        .fileExporter(isPresented: $exporting,
            document: COVICSVDocument(Self.export(goods, shopID: shop.id)),
            contentType: .commaSeparatedText, defaultFilename: "COVI-inventaire") { result in
                if case .failure(let fault) = result { exportError = fault.localizedDescription }
            }
    }

    static func export(_ goods: [CatalogItem], shopID: UUID) -> String {
        let rows: [[COVICSV.Cell]] = goods
            .filter { $0.establishmentID == shopID && !$0.isService }
            .sorted { $0.title < $1.title }
            .map { item in
                let (available, overflow) = item.stockOnHand.subtractingReportingOverflow(item.stockReserved)
                return [.text(item.id.uuidString), .text(item.title),
                 .number(String(item.priceMinor)), .number(String(item.stockOnHand)),
                 .number(String(item.stockReserved)),
                 overflow ? .text("Incohérent") : .number(String(available)),
                 .text(item.soldOut ? "Vente suspendue" : "Disponible")]
            }
        return COVICSV.encode(headers: ["Identifiant", "Article", "Prix", "Stock physique",
                                       "Réservé", "Disponible", "Vente"], rows: rows)
    }
}

@MainActor enum BoutiqueInventoryService {
    enum Fault: LocalizedError {
        case invalid, duplicate, wrongShop, permission
        var errorDescription: String? {
            switch self {
            case .invalid: "Saisissez un nom et un prix strictement positif."
            case .duplicate: "Un article portant ce nom existe déjà dans cette boutique."
            case .wrongShop: "Cet article n'appartient pas à cette boutique."
            case .permission: "Seul le propriétaire ou le responsable peut créer un article."
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

    static func checkReceive(shop: Establishment, actor: UUID, context: ModelContext) throws {
        guard shop.kind == .boutique, !shop.archived else { throw Fault.wrongShop }
        let role = try StaffAccess.role(for: actor, in: shop, context: context)
        guard role == .owner || role == .manager else { throw Fault.permission }
    }

    @discardableResult
    static func create(shop: Establishment, name: String, price: Int64,
                       actor: UUID, context: ModelContext, initialStock: Int = 0,
                       photo: BoutiquePhotoDraft? = nil, description: String = "",
                       arrivalID: UUID? = nil) throws -> CatalogItem {
        try checkReceive(shop: shop, actor: actor, context: context)
        if let arrivalID {
            let matches = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
                $0.id == arrivalID
            }))
            if let existing = matches.first {
                guard existing.establishmentID == shop.id, !existing.isService else { throw Fault.wrongShop }
                return existing
            }
            guard photo != nil, initialStock > 0 else { throw Fault.invalid }
        }
        guard initialStock >= 0 else { throw Fault.invalid }
        let cleaned = try validated(name, price, shopID: shop.id, excluding: nil, context: context)
        let item = CatalogItem(establishmentID: shop.id, title: cleaned, priceMinor: price)
        item.stockOnHand = initialStock
        if let arrivalID {
            item.id = arrivalID
            // A crash between storing the media and committing SwiftData leaves the
            // queue entry intact. Clear only the incomplete media for this same entry.
            try BoutiquePhotoStore.remove(shopID: shop.id, itemID: arrivalID)
        }
        if let photo {
            try BoutiquePhotoStore.save(photo, description: description, shopID: shop.id, itemID: item.id)
        }
        context.insert(item)
        var movements: [UUID] = []
        if initialStock > 0 {
            let movement = StockMovement(establishmentID: shop.id, itemID: item.id,
                delta: initialStock, reason: "Stock initial", actorID: actor)
            context.insert(movement); movements.append(movement.id)
        }
        do {
            try BusinessOutbox.enqueue(kind: "boutique.product.created", establishmentID: shop.id,
                entityID: item.id, actorID: actor, relatedIDs: movements, in: context)
            try context.save()
            return item
        } catch {
            context.rollback()
            if photo != nil { try? BoutiquePhotoStore.remove(shopID: shop.id, itemID: item.id) }
            throw error
        }
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

    static func setAvailability(_ item: CatalogItem, in shop: Establishment,
                                available: Bool, actor: UUID, context: ModelContext) throws {
        guard shop.kind == .boutique, !shop.archived,
              item.establishmentID == shop.id, !item.isService else { throw Fault.wrongShop }
        guard item.soldOut == available else { return }
        item.soldOut = !available
        item.updatedAt = .now
        do {
            try BusinessOutbox.enqueue(
                kind: available ? "boutique.product.reactivated" : "boutique.product.suspended",
                establishmentID: shop.id, entityID: item.id, actorID: actor, in: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

struct NewProduct: View {
    let shop: Establishment
    let actor: UUID
    var arrival: BoutiqueArrivalPhoto? = nil
    var onArrivalSaved: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var price = ""
    @State private var quantity = "0"
    @State private var description = ""
    @State private var draft: BoutiquePhotoDraft?
    @State private var analyzing = false
    @State private var error = ""

    var body: some View {
        Form {
            Section("COVI Scan") {
                if let arrival {
                    if analyzing {
                        ProgressView("Analyse de la capture…")
                    } else if draft == nil {
                        Button("Relancer l’analyse") { loadArrival(arrival) }
                    }
                } else {
                    BoutiquePhotoInput(busy: analyzing) { data in analyze { data } }
                }
                Text("Reconnaissance sur cet appareil. Vérifiez les propositions avant de créer l’article.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let draft {
                    BoutiquePhotoPreview(draft: draft)
                    if draft.suggestion != nil {
                        Label("Type proposé — à vérifier", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(COVITheme.success)
                    } else {
                        Text("Type non reconnu. Renseignez le nom manuellement.").foregroundStyle(.secondary)
                    }
                    if arrival == nil {
                        Button("Retirer la photo", role: .destructive) { self.draft = nil }
                    }
                }
            }
            Section("Fiche article") {
                TextField("Nom", text: $title)
                TextField("Prix en " + shop.currencyCode, text: $price).keyboardType(.numberPad)
                TextField("Quantité initiale", text: $quantity).keyboardType(.numberPad)
                if draft != nil {
                    TextField("Description et caractéristiques", text: $description, axis: .vertical)
                }
                Text("Le prix n'est jamais proposé automatiquement.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Créer l’article") {
                    do {
                        guard let stock = Int(quantity), stock >= 0 else { throw BoutiqueInventoryService.Fault.invalid }
                        try BoutiqueInventoryService.create(shop: shop, name: title,
                            price: Int64(price) ?? 0, actor: actor, context: context,
                            initialStock: stock, photo: draft, description: description, arrivalID: arrival?.id)
                        if let arrival {
                            try? FileManager.default.removeItem(at: arrival.url)
                            onArrivalSaved?()
                        }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(analyzing || (arrival != nil && draft == nil))
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Nouvel article")
        .task {
            if let arrival, draft == nil, !analyzing { loadArrival(arrival) }
        }
    }

    private func loadArrival(_ photo: BoutiqueArrivalPhoto) {
        do {
            try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context)
            let url = photo.url
            analyze { try Data(contentsOf: url) }
        } catch { self.error = error.localizedDescription }
    }

    private func analyze(_ load: @escaping @Sendable () throws -> Data) {
        analyzing = true; error = ""; draft = nil
        Task { @MainActor in
            defer { analyzing = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try BoutiquePhotoProcessor.process(load())
                }.value
                draft = result
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let suggestion = result.suggestion {
                    title = suggestion
                }
                if description.isEmpty, let color = result.color { description = "Couleur proposée : " + color }
                if quantity == "0" { quantity = "1" }
            } catch { self.error = error.localizedDescription }
        }
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
    @State private var availabilityChange = false
    init(shop: Establishment, item: CatalogItem, actor: UUID) {
        self.shop = shop; self.item = item; self.actor = actor
        let id = item.id
        _logs = Query(filter: #Predicate<StockMovement> { $0.itemID == id }, sort: \.createdAt, order: .reverse)
    }
    var body: some View {
        List {
            Section(item.title) {
                if let data = BoutiquePhotoStore.data(shopID: shop.id, itemID: item.id),
                   let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 240)
                        .accessibilityLabel("Photo de l’article")
                    if let description = BoutiquePhotoStore.description(shopID: shop.id, itemID: item.id),
                       !description.isEmpty { Text(description).font(.subheadline) }
                    if let studio = BoutiquePhotoStore.data(shopID: shop.id, itemID: item.id, studio: true),
                       let rendered = UIImage(data: studio) {
                        let photo = Image(uiImage: rendered)
                        ShareLink(item: photo, preview: SharePreview("Studio COVI", image: photo)) {
                            Label("Partager la photo Studio", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Text("\(item.priceMinor) \(shop.currencyCode)")
                LabeledContent("Stock · réservé", value: "\(item.stockOnHand) · \(item.stockReserved)")
                Label(item.soldOut ? "Vente suspendue" : "Disponible à la vente",
                      systemImage: item.soldOut ? "pause.circle" : "checkmark.circle")
                Button(item.soldOut ? "Remettre en vente" : "Suspendre la vente") {
                    availabilityChange = true
                }
            }
            Section("Modifier l’article") {
                TextField("Nom de l’article", text: $editedName)
                TextField("Prix " + shop.currencyCode, text: $editedPrice).keyboardType(.numberPad)
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
            .confirmationDialog(item.soldOut ? "Remettre cet article en vente ?" : "Suspendre les ventes de cet article ?",
                                isPresented: $availabilityChange) {
                Button(item.soldOut ? "Remettre en vente" : "Suspendre les ventes") {
                    do {
                        try BoutiqueInventoryService.setAvailability(item, in: shop,
                            available: item.soldOut, actor: actor, context: context)
                        message = item.soldOut ? "Vente suspendue ; historique et stock conservés." : "Article de nouveau disponible."
                    } catch { message = error.localizedDescription }
                }
            } message: {
                Text("Le stock et les reçus restent conservés. Vous pourrez réactiver la vente plus tard.")
            }
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
                TextField("Coût du lot en " + shop.currencyCode, text: $cost).keyboardType(.numberPad)
                Button("Réceptionner la balle") {
                    do { try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context) }
                    catch { message = error.localizedDescription; return }
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
                        LabeledContent("Coût du lot", value: "\(bale.cost) \(shop.currencyCode)")
                        Picker("Article découvert", selection: $picked) {
                            Text("Choisir").tag(nil as UUID?)
                            ForEach(goods) { Text($0.title).tag(Optional($0.id)) }
                        }
                        TextField("Quantité découverte", text: $units).keyboardType(.numberPad)
                        Button("Ajouter les pièces au stock") {
                            do { try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context) }
                            catch { message = error.localizedDescription; return }
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
