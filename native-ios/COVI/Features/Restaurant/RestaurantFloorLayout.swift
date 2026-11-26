import Foundation

struct RestaurantTablePlacement: Codable, Equatable {
    var slot: Int
    var shape: FloorTableDrawing.Shape
    var rotation: Int = 0

    var row: Int { slot / RestaurantFloorLayout.columns + 1 }
    var column: Int { slot % RestaurantFloorLayout.columns + 1 }
    var isValid: Bool { (0..<RestaurantFloorLayout.maximumSlots).contains(slot) && (0..<4).contains(rotation) }
}

struct RestaurantFloorLayout: Codable {
    static let columns = 3
    static let maximumSlots = 600
    var placements: [UUID: RestaurantTablePlacement] = [:]

    init() {}

    init(stored data: Data) throws {
        self = data.isEmpty ? Self() : try JSONDecoder().decode(Self.self, from: data)
        guard placements.values.allSatisfy(\.isValid),
              Set(placements.values.map(\.slot)).count == placements.count
        else { throw RestaurantFault.invalid }
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    func resolved(tables: [DiningTable]) -> [UUID: RestaurantTablePlacement] {
        let active = Set(tables.map(\.id))
        var result = placements.filter { active.contains($0.key) }
        var occupied = Set(result.values.map(\.slot))
        var nextSlot = 0
        for table in tables where result[table.id] == nil {
            while occupied.contains(nextSlot) { nextSlot += 1 }
            result[table.id] = RestaurantTablePlacement(slot: nextSlot, shape: .init(capacity: table.capacity))
            occupied.insert(nextSlot)
        }
        return result
    }

    mutating func place(_ requested: RestaurantTablePlacement, tableID: UUID, tables: [DiningTable]) throws {
        var current = resolved(tables: tables)
        guard requested.isValid, let previous = current[tableID] else { throw RestaurantFault.invalid }
        if let other = current.first(where: { $0.key != tableID && $0.value.slot == requested.slot }) {
            var swapped = other.value
            swapped.slot = previous.slot
            current[other.key] = swapped
        }
        guard current.values.allSatisfy(\.isValid) else { throw RestaurantFault.invalid }
        current[tableID] = requested
        placements = current
    }
}
