import SwiftUI

struct RestaurantFloorEditor: View {
    let table: DiningTable
    let spaces: [RestaurantFloorRoom]
    let otherPositions: [RestaurantTablePlacement]
    let save: (RestaurantTablePlacement) throws -> Void
    @Environment(\.dismiss) private var dismiss
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @State private var placement: RestaurantTablePlacement
    @State private var message = ""

    init(table: DiningTable, placement: RestaurantTablePlacement, spaces: [RestaurantFloorRoom],
         otherPositions: [RestaurantTablePlacement], save: @escaping (RestaurantTablePlacement) throws -> Void) {
        self.table = table
        self.spaces = spaces
        self.otherPositions = otherPositions
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
                    if !spaces.isEmpty {
                        Picker("Espace", selection: room) {
                            Text(RestaurantFloorLayout.mainRoomName).tag(nil as UUID?)
                            ForEach(spaces) { space in
                                Label(space.name, systemImage: space.kind.symbol).tag(Optional(space.id))
                            }
                        }
                    }
                    Stepper("Rangée : \(placement.row)", value: row, in: 1...maximumRow)
                    Picker("Colonne", selection: column) {
                        ForEach(1...RestaurantFloorLayout.columns, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } footer: {
                    Text("Dans le même espace, deux tables peuvent échanger leurs cases. Pour changer d’espace, choisissez une case libre.")
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
        let last = otherPositions.filter { $0.roomID == placement.roomID }.map(\.slot).max() ?? 0
        return min(limit, max(placement.row, last / RestaurantFloorLayout.columns + 2))
    }

    private var room: Binding<UUID?> {
        Binding(get: { placement.roomID }, set: { newRoom in
            guard placement.roomID != newRoom else { return }
            let occupied = Set(otherPositions.filter { $0.roomID == newRoom }.map(\.slot))
            if let firstFree = (0..<RestaurantFloorLayout.maximumSlots).first(where: { !occupied.contains($0) }) {
                placement.roomID = newRoom
                placement.slot = firstFree
            } else {
                message = RestaurantFault.floorSlotOccupied.localizedDescription
            }
        })
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

struct RestaurantFloorRoomEditor: View {
    let existing: RestaurantFloorRoom?
    let save: (String, RestaurantFloorRoom.Kind) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: RestaurantFloorRoom.Kind
    @State private var message = ""

    init(existing: RestaurantFloorRoom?, save: @escaping (String, RestaurantFloorRoom.Kind) throws -> Void) {
        self.existing = existing
        self.save = save
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .indoor)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l’espace", text: $name).textInputAutocapitalization(.sentences)
                if existing == nil {
                    Picker("Type", selection: $kind) {
                        ForEach(RestaurantFloorRoom.Kind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(COVITheme.cream)
            .navigationTitle(existing == nil ? "Ajouter un espace" : "Renommer l’espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        do {
                            try save(name, kind)
                            HapticService.confirm()
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                            HapticService.error()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
