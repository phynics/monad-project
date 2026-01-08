import Foundation
import SwiftUI
import MonadCore

extension ChatViewModel {
    public var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        let availableTools: [MonadCore.Tool] = [
            SearchArchivedChatsTool(persistenceService: persistenceManager.persistence),
            LoadArchivedChatTool(persistenceService: persistenceManager.persistence, documentManager: documentManager),
            ViewChatHistoryTool(persistenceService: persistenceManager.persistence, currentSessionProvider: { [weak self] in
                await MainActor.run {
                    return self?.persistenceManager.currentSession?.id
                }
            }),
            SearchMemoriesTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            CreateMemoryTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            SearchNotesTool(persistenceService: persistenceManager.persistence),
            EditNoteTool(persistenceService: persistenceManager.persistence),
            // Filesystem Tools
            ListDirectoryTool(),
            FindFileTool(),
            SearchFileContentTool(),
            ReadFileTool(),
            InspectFileTool(),
            // Document Tools
            LoadDocumentTool(documentManager: documentManager),
            UnloadDocumentTool(documentManager: documentManager),
            SwitchDocumentViewTool(documentManager: documentManager),
            FindExcerptsTool(llmService: llmService, documentManager: documentManager),
            EditDocumentSummaryTool(documentManager: documentManager),
            MoveDocumentExcerptTool(documentManager: documentManager),
            LaunchSubagentTool(llmService: llmService, documentManager: documentManager)
        ]
        let manager = SessionToolManager(availableTools: availableTools)
        self.setToolManager(manager)
        self.toolExecutor = ToolExecutor(toolManager: manager)
        return manager
    }
}
