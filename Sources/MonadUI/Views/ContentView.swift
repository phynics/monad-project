import MonadCore
import OSLog
import OpenAI
import SwiftUI

public struct ContentView: View {
    @Bindable public var viewModel: ChatViewModel
    public var llmService: LLMService
    public var persistenceManager: PersistenceManager

    @State private var showingArchive = false
    @State private var showingNotes = false
    @State private var showingMemories = false
    @State private var showingTools = false
    @State private var showingArchiveConfirmation = false

    @Environment(\.openWindow) private var openWindow

    public init(viewModel: ChatViewModel, llmService: LLMService, persistenceManager: PersistenceManager) {
        self.viewModel = viewModel
        self.llmService = llmService
        self.persistenceManager = persistenceManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                llmService: llmService,
                messagesEmpty: viewModel.messages.isEmpty,
                onArchive: { showingArchive = true },
                onNotes: { showingNotes = true },
                onMemories: { showingMemories = true },
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
                documentManager: viewModel.documentManager,
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
        .sheet(isPresented: $showingMemories) {
            MemoriesView(persistenceManager: persistenceManager)
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
