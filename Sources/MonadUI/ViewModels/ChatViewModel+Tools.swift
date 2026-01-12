import Foundation
import MonadCore
import SwiftUI

extension ChatViewModel {
    /// Creates the tool manager with all available tools
    func createToolManager() -> SessionToolManager {
        let currentWD =
            persistenceManager.currentSession?.workingDirectory
            ?? FileManager.default.currentDirectoryPath

        let availableTools: [MonadCore.Tool] = [
            ExecuteSQLTool(persistenceService: persistenceManager.persistence, confirmationDelegate: self),
            // Filesystem Tools
            ChangeDirectoryTool(
                currentPath: currentWD,
                onChange: { [weak self] newPath in
                    guard let self = self else { return }
                    try? await self.persistenceManager.updateWorkingDirectory(newPath)
                    await MainActor.run {
                        self.invalidateToolInfrastructure()
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
            JobQueueGatewayTool(context: jobQueueContext, contextSession: toolContextSession),
        ]

        return SessionToolManager(
            availableTools: availableTools, contextSession: toolContextSession)
    }

    /// Creates the tool executor
    func createToolExecutor() -> ToolExecutor {
        return ToolExecutor(
            toolManager: toolManager,
            contextSession: toolContextSession,
            jobQueueContext: jobQueueContext
        )
    }
}
