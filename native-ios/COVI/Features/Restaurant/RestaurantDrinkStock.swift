import SwiftUI
import SwiftData

struct RestaurantDrinkStock: View {
    let service: RestaurantService
    @Query private var drinks: [CatalogItem]
    @Query private var movements: [StockMovement]
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var operation: DrinkStockOperation?
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    init(service: RestaurantService) {
        self.service = service
        let shopID = service.shop.id
        let category: String? = MenuGroup.drinks.rawValue
        _drinks = Query(filter: #Predicate<CatalogItem> {
            $0.establishmentID == shopID && $0.menuCategory == category
        }, sort: \.title)
        _movements = Query(filter: #Predicate<StockMovement> { $0.establishmentID == shopID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Les boissons suivies sont réservées à la commande et déduites du stock au service.",
                      systemImage: "info.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 14))
                if drinks.isEmpty {
                    ContentUnavailableView("Aucune boisson", systemImage: "wineglass",
                        description: Text("Ajoutez une boisson dans Gestion de la carte."))
                } else {
                    let counted = Set(movements.map(\.itemID))
                    COVICard {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(drinks) { drink in
                                if drink.id != drinks.first?.id { Divider() }
                                drinkRow(drink, recorded: counted.contains(drink.id))
                            }
                        }
                    }
                    COVIButton("Déclarer une casse ou perte boisson", systemImage: "exclamationmark.triangle",
                               role: .secondary) {
                        operation = .loss
                    }
                    .disabled(!drinks.contains(where: { $0.stockReserved >= 0 && $0.stockOnHand > $0.stockReserved }))
                    .padding(.top, 8)
                }
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
        }
        .background(COVIBackdrop())
        .navigationTitle("Stock boissons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Réassort") { operation = .restock }
                    .buttonStyle(.borderedProminent)
                    .tint(COVITheme.navy)
                    .disabled(drinks.isEmpty)
            }
        }
        .sheet(item: $operation) { operation in
            NavigationStack {
                RestaurantDrinkAdjustment(service: service, operation: operation, drinks: drinks)
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .restaurantDrinks {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private func drinkRow(_ drink: CatalogItem, recorded: Bool) -> some View {
        let layout = textSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        let balance = RestaurantDrinkBalance(onHand: drink.stockOnHand, reserved: drink.stockReserved,
                                            hasMovements: recorded)
        return layout {
            Image(systemName: "wineglass")
                .font(.title3)
                .frame(width: 46, height: 52)
                .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(drink.title).font(.subheadline.weight(.bold))
                if balance != .untracked {
                    Text("Physique : \(drink.stockOnHand) · Réservées : \(drink.stockReserved)")
                        .font(.caption)
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch balance {
            case .untracked:
                COVIBadge(title: "Non suivi")
            case .invalid:
                COVIBadge(title: "À vérifier", tint: COVITheme.dangerTint, foreground: .red)
            case .tracked(0):
                COVIBadge(title: "0 disp.", tint: COVITheme.dangerTint, foreground: .red)
                    .accessibilityLabel("0 disponible")
            case .tracked(let available) where available <= 10:
                COVIBadge(title: "\(available) disp. · Faible", tint: COVITheme.warningTint,
                          foreground: COVITheme.warning)
                    .accessibilityLabel("\(available) disponibles. Stock faible.")
            case .tracked(let available):
                COVIBadge(title: "\(available) disp.", tint: COVITheme.successTint,
                          foreground: COVITheme.success)
                    .accessibilityLabel("\(available) disponibles")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RestaurantDrinkAdjustment: View {
    let service: RestaurantService
    let operation: DrinkStockOperation
    let drinks: [CatalogItem]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var quantity = ""
    @State private var error = ""
    @State private var saved = false

    private var options: [CatalogItem] {
        drinks.filter {
            $0.menuCategory == MenuGroup.drinks.rawValue && $0.stockReserved >= 0 &&
            $0.stockOnHand >= $0.stockReserved &&
            (operation == .restock || $0.stockOnHand > $0.stockReserved)
        }
    }

    var body: some View {
        let selected = options.first { $0.id == selectedID }
        let units = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        Form {
            Picker("Boisson", selection: $selectedID) {
                Text("Choisir").tag(nil as UUID?)
                ForEach(options) { drink in
                    Text(drink.title).tag(Optional(drink.id))
                }
            }
            TextField("Quantité", text: $quantity)
                .keyboardType(.numberPad)
            if let selected, operation == .loss {
                LabeledContent("Disponible", value: String(selected.stockOnHand - selected.stockReserved))
            }
            if !error.isEmpty {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle(operation.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    guard !saved, let selected else { return }
                    do {
                        try service.adjustDrinkStock(selected, operation: operation, quantity: units)
                        saved = true
                        HapticService.confirm()
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                        HapticService.error()
                    }
                }
                .disabled(saved || selected == nil || units <= 0)
            }
        }
    }
}
