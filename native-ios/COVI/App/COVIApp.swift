import SwiftUI
import SwiftData

@MainActor
@main struct COVIApp: App {
    @State private var session: AppSession
    private let container: ModelContainer?
#if DEBUG && targetEnvironment(simulator)
    private let diagnostics: COVISimulatorDiagnostics?
#endif

    init() {
        COVITabAppearance.install()
#if DEBUG && targetEnvironment(simulator)
        // La demande de capture est traitée avant toute ouverture du stockage réel.
        // Une erreur de fixture ne doit jamais revenir au compte ou au disque réels.
        if ProcessInfo.processInfo.arguments.contains(COVISimulatorDiagnostics.argument) {
            let fixture = try? COVISimulatorDiagnostics(arguments: ProcessInfo.processInfo.arguments)
            diagnostics = fixture
            container = fixture?.container
            _session = State(initialValue: fixture?.session ??
                AppSession(keychain: COVISimulatorMemoryStore()))
            return
        }
        diagnostics = nil
#endif
        _session = State(initialValue: AppSession())
        container = try? PersistenceController.makeContainer()
    }

    @ViewBuilder private var content: some View {
#if DEBUG && targetEnvironment(simulator)
        if let diagnostics {
            COVISimulatorDiagnosticView(fixture: diagnostics)
        } else {
            RootView()
        }
#else
        RootView()
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    content
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
            // Les maquettes COVI sont ivoire/bleu nuit. Les couleurs de texte,
            // List et ContentUnavailableView natives suivent sinon le mode
            // sombre du téléphone et deviennent illisibles sur ce fond clair.
            .preferredColorScheme(.light)
        }
    }
}

