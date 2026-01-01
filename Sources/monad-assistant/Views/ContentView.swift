import OSLog
import OpenAI
import SwiftUI

struct ContentView: View {
    @State private var viewModel: ChatViewModel
    var llmService: LLMService
    var persistenceManager: PersistenceManager

    @State private var showingArchive = false
    @State private var showingNotes = false
    @State private var showingTools = false
    @State private var showingArchiveConfirmation = false

    @Environment(\.openWindow) private var openWindow

    init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        _viewModel = State(
            wrappedValue: ChatViewModel(
                llmService: llmService, persistenceManager: persistenceManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                llmService: llmService,
                messagesEmpty: viewModel.messages.isEmpty,
                onArchive: { showingArchive = true },
                onNotes: { showingNotes = true },
                onClear: viewModel.clearConversation,
                onArchiveCurrent: { showingArchiveConfirmation = true },
                onSettings: { openWindow(id: "settings") },
                onTools: { showingTools = true }
            )

            MessageListView(
                messages: viewModel.messages,
                isStreaming: viewModel.isStreaming,
                streamingThinking: viewModel.streamingThinking,
                streamingContent: viewModel.streamingContent,
                isLoading: viewModel.isLoading,
                llmServiceConfigured: llmService.isConfigured,
                onConfigureSettings: { openWindow(id: "settings") }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ChatErrorMessageView(errorMessage: $viewModel.errorMessage)

            ChatInputView(
                inputText: $viewModel.inputText,
                isLoading: viewModel.isLoading,
                isStreaming: viewModel.isStreaming,
                llmServiceConfigured: llmService.isConfigured,
                onSend: viewModel.sendMessage,
                onCancel: viewModel.cancelGeneration
            )
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showingArchive) {
            ArchivedConversationsView(persistenceManager: persistenceManager)
        }
        .sheet(isPresented: $showingNotes) {
            NotesView(persistenceManager: persistenceManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $showingTools) {
            ToolsSettingsView(
                toolManager: viewModel.tools,
                availableTools: viewModel.tools.getEnabledTools()
            )
        }
        .confirmationDialog(
            "Archive this conversation?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive") {
                viewModel.archiveConversation {
                    showingArchiveConfirmation = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save the current conversation to your archives.")
        }
    }
}
