import SwiftUI

struct RestaurantFloorEditor: View {
    let table: DiningTable
    let lastSlot: Int
    let save: (RestaurantTablePlacement) throws -> Void
    @Environment(\.dismiss) private var dismiss
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var placement: RestaurantTablePlacement
    @State private var message = ""

    init(table: DiningTable, placement: RestaurantTablePlacement, lastSlot: Int,
         save: @escaping (RestaurantTablePlacement) throws -> Void) {
        self.table = table
        self.lastSlot = lastSlot
        self.save = save
        _placement = State(initialValue: placement)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Forme", selection: $placement.shape) {
                        ForEach(FloorTableDrawing.Shape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    Picker("Rotation", selection: $placement.rotation) {
                        ForEach(0..<4) { quarter in
                            Text("\(quarter * 90)°").tag(quarter)
                        }
                    }
                    LabeledContent("Capacité", value: "\(table.capacity) places")
                }
                Section {
                    Stepper("Rangée : \(placement.row)", value: row, in: 1...maximumRow)
                    Picker("Colonne", selection: column) {
                        ForEach(1...RestaurantFloorLayout.columns, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } footer: {
                    Text("Dans une case occupée, les deux tables échangent leur emplacement.")
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(COVITheme.cream)
            .navigationTitle(table.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        do {
                            try save(placement)
                            HapticService.confirm()
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                            HapticService.error()
                        }
                    }
                }
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .restaurantFloorEdit {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private var maximumRow: Int {
        let limit = RestaurantFloorLayout.maximumSlots / RestaurantFloorLayout.columns
        return min(limit, lastSlot / RestaurantFloorLayout.columns + 2)
    }

    private var row: Binding<Int> {
        Binding(get: { placement.row }, set: { newRow in
            placement.slot = (newRow - 1) * RestaurantFloorLayout.columns + (placement.column - 1)
        })
    }

    private var column: Binding<Int> {
        Binding(get: { placement.column }, set: { newColumn in
            placement.slot = (placement.row - 1) * RestaurantFloorLayout.columns + (newColumn - 1)
        })
    }
}
