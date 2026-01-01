import Shared
import SwiftUI

@main
struct MonadAssistantApp: App {
    @State private var llmService = LLMService()
    @State private var persistenceManager: PersistenceManager

    init() {
        let persistence = try! PersistenceService.create()
        let manager = PersistenceManager(persistence: persistence)
        self._persistenceManager = State(initialValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                llmService: llmService,
                persistenceManager: persistenceManager
            )
        }
    }
}
