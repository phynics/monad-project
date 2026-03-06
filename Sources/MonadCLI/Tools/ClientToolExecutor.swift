import Foundation
import MonadClient
import MonadShared

/// Executes tools locally on the client machine for attached workspaces.
struct ClientToolExecutor {
    let client: MonadClient
    let session: Session
    let repl: ChatREPL
    
    init(client: MonadClient, session: Session, repl: ChatREPL) {
        self.client = client
        self.session = session
        self.repl = repl
    }
    
    func execute(toolCalls: [ToolCall], in workspace: WorkspaceReference) async -> [ToolOutputSubmission] {
        var submissions: [ToolOutputSubmission] = []
        let rootPath = workspace.rootPath ?? FileManager.default.currentDirectoryPath
        
        for call in toolCalls {
            // Internal REPL interaction tool
            if call.name == "request_write_access" {
                let submission = await handleRequestWriteAccess(toolCall: call, workspace: workspace)
                submissions.append(submission)
                continue
            }
            
            // Standard shared tools
            guard let tool = instantiateTool(name: call.name, rootPath: rootPath) else {
                submissions.append(ToolOutputSubmission(
                    toolCallId: call.id.uuidString,
                    output: "Error: Tool '\(call.name)' not found or not supported on this client."
                ))
                continue
            }
            
            do {
                let dict = call.arguments.mapValues { $0.value }
                let result = try await tool.execute(parameters: dict)
                submissions.append(ToolOutputSubmission(
                    toolCallId: call.id.uuidString,
                    output: result.output
                ))
            } catch {
                submissions.append(ToolOutputSubmission(
                    toolCallId: call.id.uuidString,
                    output: "Error executing tool: \(error.localizedDescription)"
                ))
            }
        }
        
        return submissions
    }
    
    private func handleRequestWriteAccess(toolCall: ToolCall, workspace: WorkspaceReference) async -> ToolOutputSubmission {
        let reason = toolCall.arguments["reason"]?.value as? String ?? "No reason provided."
        
        let answer = await repl.promptForWriteAccess(reason: reason, workspaceURI: workspace.uri.description)
        
        guard answer else {
            return ToolOutputSubmission(
                toolCallId: toolCall.id.uuidString,
                output: "User denied write access."
            )
        }
        
        do {
            // Update workspace to full trust
            _ = try await client.workspace.updateWorkspace(
                id: workspace.id,
                trustLevel: .full
            )
            
            // Sync read/write tools
            try await client.workspace.syncWorkspaceTools(
                ClientConstants.readOnlyToolReferences + ClientConstants.readWriteToolReferences,
                workspaceId: workspace.id
            )
            
            return ToolOutputSubmission(
                toolCallId: toolCall.id.uuidString,
                output: "Write access granted successfully. You may now use write-enabled tools."
            )
        } catch {
            return ToolOutputSubmission(
                toolCallId: toolCall.id.uuidString,
                output: "Error upgrading workspace trust level: \(error.localizedDescription)"
            )
        }
    }
    
    private func instantiateTool(name: String, rootPath: String) -> MonadShared.Tool? {
        // Shared filesystem tools require currentDirectory and jailRoot initialization
        switch name {
        case "ls": return ListDirectoryTool(currentDirectory: rootPath, jailRoot: rootPath)
        case "cat": return ReadFileTool(currentDirectory: rootPath, jailRoot: rootPath)
        case "grep": return SearchFileContentTool(currentDirectory: rootPath, jailRoot: rootPath)
        case "find": return FindFileTool(currentDirectory: rootPath, jailRoot: rootPath)
        case "search_files": return SearchFilesTool(currentDirectory: rootPath, jailRoot: rootPath)
        case "inspect_file": return InspectFileTool(currentDirectory: rootPath, jailRoot: rootPath)
        // case "write_file": return WriteFileTool(...)
        // Add future write tools here when they are implemented in MonadShared:
        // case "write_file": return WriteFileTool(...)
        default: return nil
        }
    }
}
