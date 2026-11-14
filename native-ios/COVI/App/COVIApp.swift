import SwiftUI
import SwiftData

@MainActor
@main struct COVIApp: App {
    @State private var session = AppSession()
    private let container: ModelContainer
    init() {
        do { container = try PersistenceController.makeContainer() }
        catch { fatalError("Unable to initialize local database: \(error)") }
    }
    var body: some Scene {
        WindowGroup { RootView().environment(session) }
            .modelContainer(container)
    }
}
