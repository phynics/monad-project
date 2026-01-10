import Foundation
import MonadCore
import SwiftUI

extension ChatViewModel {
    public var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        let currentWD =
            persistenceManager.currentSession?.workingDirectory
            ?? FileManager.default.currentDirectoryPath

        // Create the shared JobQueueContext for the session
        let jobQueueContext = JobQueueContext()

        // Create the ToolContextSession for managing context lifecycles
        let contextSession = ToolContextSession()

        let availableTools: [MonadCore.Tool] = [
            SearchArchivedChatsTool(persistenceService: persistenceManager.persistence),
            LoadArchivedChatTool(
                persistenceService: persistenceManager.persistence, documentManager: documentManager
            ),
            ViewChatHistoryTool(
                persistenceService: persistenceManager.persistence,
                currentSessionProvider: { [weak self] in
                    await MainActor.run {
                        return self?.persistenceManager.currentSession?.id
                    }
                }),
            SearchMemoriesTool(
                persistenceService: persistenceManager.persistence,
                embeddingService: llmService.embeddingService),
            CreateMemoryTool(
                persistenceService: persistenceManager.persistence,
                embeddingService: llmService.embeddingService),
            SearchNotesTool(persistenceService: persistenceManager.persistence),
            EditNoteTool(persistenceService: persistenceManager.persistence),
            // Filesystem Tools
            ChangeDirectoryTool(
                currentPath: currentWD,
                onChange: { [weak self] newPath in
                    guard let self = self else { return }
                    try? await self.persistenceManager.updateWorkingDirectory(newPath)
                    await MainActor.run {
                        self.toolManager = nil  // Invalidate cache to recreate tools with new root
                        self.toolExecutor = nil
                    }
                }),
            ListDirectoryTool(root: currentWD),
            FindFileTool(root: currentWD),
            SearchFileContentTool(root: currentWD),
            ReadFileTool(root: currentWD),
            InspectFileTool(root: currentWD),
            // Document Tools
            LoadDocumentTool(documentManager: documentManager),
            UnloadDocumentTool(documentManager: documentManager),
            SwitchDocumentViewTool(documentManager: documentManager),
            FindExcerptsTool(llmService: llmService, documentManager: documentManager),
            EditDocumentSummaryTool(documentManager: documentManager),
            MoveDocumentExcerptTool(documentManager: documentManager),
            LaunchSubagentTool(llmService: llmService, documentManager: documentManager),
            DetectTopicChangeTool(),
            // Job Queue Gateway
            JobQueueGatewayTool(context: jobQueueContext, contextSession: contextSession),
        ]
        let manager = SessionToolManager(
            availableTools: availableTools, contextSession: contextSession)
        self.setToolManager(manager)
        self.toolExecutor = ToolExecutor(
            toolManager: manager, contextSession: contextSession, jobQueueContext: jobQueueContext)
        return manager
    }
}
