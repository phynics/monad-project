import MonadCore
import MonadUI
import SwiftUI

@main
struct MonadAssistantApp: App {
    @State private var llmService = LLMService()
    @State private var persistenceManager: PersistenceManager
    @State private var chatViewModel: ChatViewModel
    
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let persistence = try! PersistenceService.create()
        let manager = PersistenceManager(persistence: persistence)
        self._persistenceManager = State(initialValue: manager)
        
        let llm = LLMService()
        self._llmService = State(initialValue: llm)
        
        self._chatViewModel = State(initialValue: ChatViewModel(llmService: llm, persistenceManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: chatViewModel,
                llmService: llmService,
                persistenceManager: persistenceManager
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                chatViewModel.archiveConversation { }
            }
        }
    }
}
