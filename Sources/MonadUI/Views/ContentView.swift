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
    @State private var showSidebar = true

    @Environment(\.openWindow) private var openWindow

    public init(
        viewModel: ChatViewModel, llmService: LLMService, persistenceManager: PersistenceManager
    ) {
        self.viewModel = viewModel
        self.llmService = llmService
        self.persistenceManager = persistenceManager
    }

    public var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                ChatSidebarView(viewModel: viewModel)
                    .transition(.move(edge: .leading))

                Divider()
            }

            VStack(spacing: 0) {
                ChatHeaderView(
                    llmManager: viewModel.llmManager,
                    showSidebar: $showSidebar,
                    performanceMetrics: viewModel.performanceMetrics,
                    messagesEmpty: viewModel.messages.isEmpty,
                    onArchive: { showingArchive = true },
                    onNotes: { showingNotes = true },
                    onMemories: { showingMemories = true },
                    onClear: viewModel.clearConversation,
                    onArchiveCurrent: { showingArchiveConfirmation = true },
                    onSettings: { openWindow(id: "settings") },
                    onTools: { showingTools = true },
                    onCompress: { scope in
                        Task { await viewModel.compressContext(scope: scope) }
                    },
                    onVacuum: {
                        Task { await viewModel.triggerMemoryVacuum() }
                    }
                )

                MessageListView(
                    viewModel: viewModel,
                    llmServiceConfigured: viewModel.llmManager.isConfigured,
                    onConfigureSettings: { openWindow(id: "settings") }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ChatErrorMessageView(
                    errorMessage: $viewModel.errorMessage,
                    onRetry: viewModel.retry
                )

                ChatInputView(viewModel: viewModel)
            }
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
                toolManager: viewModel.toolManager
            )
        }
        .confirmationDialog(
            "Start new conversation?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start New") {
                viewModel.archiveConversation {
                    showingArchiveConfirmation = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current conversation is already saved in history.")
        }
        .confirmationDialog(
            "Execute Sensitive SQL?",
            isPresented: $viewModel.showSQLConfirmation,
            titleVisibility: .visible
        ) {
            Button("Execute", role: .destructive) {
                viewModel.pendingSQLOperation?.onConfirm()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingSQLOperation?.onCancel()
            }
        } message: {
            if let sql = viewModel.pendingSQLOperation?.sql {
                Text("The agent wants to execute a sensitive SQL command:\n\n\(sql)")
            } else {
                Text("The agent wants to execute a sensitive SQL command.")
            }
        }
    }
}
