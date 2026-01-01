import SwiftUI

@main
struct MonadAssistantApp: App {
    @State private var llmService = LLMService()
    @State private var persistenceManager: PersistenceManager = {
        let persistence = try! PersistenceService.create()
        return PersistenceManager(persistence: persistence)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(
                llmService: llmService,
                persistenceManager: persistenceManager
            )
        }

        // Separate Settings Window - works better on macOS for text field focus
        Window("Settings", id: "settings") {
            SettingsView(llmService: llmService, persistenceManager: persistenceManager)
                .frame(minWidth: 600, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 600)
    }
}
