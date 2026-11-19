import SwiftUI
import SwiftData

@MainActor
@main struct COVIApp: App {
    @State private var session = AppSession()
    private let container: ModelContainer?
    init() {
        container = try? PersistenceController.makeContainer()
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .environment(session)
                    .modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label("Données temporairement indisponibles", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("COVI n'a pas pu ouvrir le stockage sécurisé de cet iPhone. Vos données n'ont pas été effacées.")
                } actions: {
                    Text("Vérifiez l'espace libre, puis fermez et rouvrez COVI. Si le problème persiste, contactez l'assistance.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
