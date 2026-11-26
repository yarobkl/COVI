import Foundation

struct RestaurantFloorRoom: Codable, Equatable, Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case indoor = "Salle"
        case outdoor = "Terrasse"

        var symbol: String { self == .indoor ? "door.left.hand.closed" : "sun.max" }
    }

    let id: UUID
    var name: String
    let kind: Kind
}

struct RestaurantTablePlacement: Codable, Equatable {
    var slot: Int
    var shape: FloorTableDrawing.Shape
    var rotation: Int = 0
    var roomID: UUID? = nil

    var row: Int { slot / RestaurantFloorLayout.columns + 1 }
    var column: Int { slot % RestaurantFloorLayout.columns + 1 }
    var isValid: Bool { (0..<RestaurantFloorLayout.maximumSlots).contains(slot) && (0..<4).contains(rotation) }
}

struct RestaurantFloorLayout: Codable {
    static let mainRoomName = "Salle principale"
    static let columns = 3
    static let maximumSlots = 600
    private struct Position: Hashable {
        let roomID: UUID?
        let slot: Int
    }

    private(set) var placements: [UUID: RestaurantTablePlacement] = [:]
    private var rooms: [RestaurantFloorRoom]?
    var spaces: [RestaurantFloorRoom] { rooms ?? [] }

    init() {}

    init(stored data: Data) throws {
        self = data.isEmpty ? Self() : try JSONDecoder().decode(Self.self, from: data)
        let roomIDs = Set(spaces.map(\.id))
        let seats = Set(placements.values.map { Position(roomID: $0.roomID, slot: $0.slot) })
        guard roomIDs.count == spaces.count, seats.count == placements.count,
              placements.values.allSatisfy({ placement in
                  placement.isValid && (placement.roomID.map(roomIDs.contains) ?? true)
              }) else { throw RestaurantFault.invalid }
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    func resolved(tables: [DiningTable]) -> [UUID: RestaurantTablePlacement] {
        let active = Set(tables.map(\.id))
        var result = placements.filter { active.contains($0.key) }
        var occupied = Set(result.values.filter { $0.roomID == nil }.map(\.slot))
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
        guard requested.isValid, let previous = current[tableID],
              requested.roomID == nil || spaces.contains(where: { $0.id == requested.roomID })
        else { throw RestaurantFault.invalid }
        if let other = current.first(where: {
            $0.key != tableID && $0.value.roomID == requested.roomID && $0.value.slot == requested.slot
        }) {
            guard previous.roomID == requested.roomID else { throw RestaurantFault.floorSlotOccupied }
            var swapped = other.value
            swapped.slot = previous.slot
            current[other.key] = swapped
        }
        guard current.values.allSatisfy(\.isValid) else { throw RestaurantFault.invalid }
        current[tableID] = requested
        placements = current
    }

    @discardableResult
    mutating func addRoom(name: String, kind: RestaurantFloorRoom.Kind) throws -> RestaurantFloorRoom {
        let result = RestaurantFloorRoom(id: UUID(), name: try validName(name), kind: kind)
        rooms = spaces + [result]
        return result
    }

    mutating func renameRoom(_ id: UUID, name: String) throws {
        var current = spaces
        guard let index = current.firstIndex(where: { $0.id == id }) else { throw RestaurantFault.invalid }
        current[index].name = try validName(name, excluding: id)
        rooms = current
    }

    private func validName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 40,
              cleaned.localizedStandardCompare(Self.mainRoomName) != .orderedSame,
              !spaces.contains(where: { $0.id != id && $0.name.localizedStandardCompare(cleaned) == .orderedSame })
        else { throw RestaurantFault.floorRoomName }
        return cleaned
    }
}
