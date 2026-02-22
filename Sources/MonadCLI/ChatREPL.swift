import MonadShared
import Foundation
import MonadClient
import MonadCore

// Needed for fflush
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The main Request-Eval-Print Loop for the Chat Interface
actor ChatREPL: ChatREPLController {
    private let client: MonadClient
    private var session: Session
    private var running = true
    private var selectedWorkspaceId: UUID?
    private var lastDebugSnapshot: DebugSnapshot?

    // Slash Command Registry
    private let registry = SlashCommandRegistry()
    private let lineReader = LineReader()
    
    /// The currently active generation task
    private var currentGenerationTask: Task<Void, Never>?

    init(client: MonadClient, session: Session) {
        self.client = client
        self.session = session
    }

    private func registerCommands() async {
        // Core
        await registry.register(HelpCommand(registry: registry))
        await registry.register(QuitCommand())
        await registry.register(StatusCommand())
        await registry.register(NewSessionCommand())
        await registry.register(SessionCommand())
        await registry.register(ConfigCommand())
        await registry.register(CancelCommand())

        // File System
        await registry.register(LsCommand())
        await registry.register(CatCommand())
        await registry.register(RmCommand())
        await registry.register(WriteCommand())
        await registry.register(EditCommand())

        // Tools & Env
        await registry.register(ToolCommand())
        await registry.register(WorkspaceSlashCommand())
        await registry.register(MemoryCommand())
        await registry.register(PruneSlashCommand())
        await registry.register(ClientCommand())
        await registry.register(JobSlashCommand())
        
        // Utilities
        await registry.register(ClearCommand())
        await registry.register(DebugCommand())
    }

    func run() async throws {
        // Set up signal handler for Ctrl+C
        setupSignalHandler()

        // Register commands first
        await registerCommands()

        // Ensure client is registered and intrinsic tools are active
        _ = try? await RegistrationManager.shared.ensureRegistered(client: client)

        // Show active context (memories, documents) at startup
        await showContext()
        await checkAndRestoreWorkspaces()

        while running {
            // Read input with vi-style editing via readline
            guard let input = await readInput() else {
                continue
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                continue
            }

            // Handle :q vim-style quit shortcut
            if trimmed == ":q" || trimmed == ":quit" {
                running = false
                TerminalUI.printInfo("Goodbye!")
                break
            }

            // Handle slash commands
            if trimmed.hasPrefix("/") {
                await handleSlashCommand(trimmed)
                continue
            }

            // Send message
            await sendMessage(trimmed)
        }
    }

    private func setupSignalHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.cancelCurrentGeneration()
            }
        }
        source.resume()
        // Ignore SIGINT in the main process to prevent it from killing us
        signal(SIGINT, SIG_IGN)
    }

    public func cancelCurrentGeneration() async {
        if let task = currentGenerationTask {
            task.cancel()
            currentGenerationTask = nil
            TerminalUI.printWarning("\n[Cancelling generation...]")
            try? await client.cancelChat(sessionId: session.id)
        }
    }

    private func sendMessage(_ message: String) async {
        let sessionId = session.id
        currentGenerationTask = Task {
            do {
                print("")

                let stream = try await client.chatStream(sessionId: sessionId, message: message)

                var toolCallState: [Int: (name: String, args: String)] = [:]
                var assistantStartPrinted = false

                for try await delta in stream {
                    if Task.isCancelled { break }

                    switch delta.type {
                    case .generationContext:
                        if let metadata = delta.metadata {
                            if !metadata.memories.isEmpty || !metadata.files.isEmpty {
                                let memories = metadata.memories.count
                                let files = metadata.files.count
                                print(TerminalUI.dim("Using \(memories) memories and \(files) files"))
                            }
                        }
                        
                    case .thought:
                        if let thought = delta.thought {
                            if !assistantStartPrinted {
                                // Indicate reasoning phase
                                print(TerminalUI.dim("🤔 Thinking..."))
                                assistantStartPrinted = true
                            }
                            // Optionally print thinking chunk-by-chunk if verbose, or just keep it silent/dim
                            print(TerminalUI.dim(thought), terminator: "")
                            fflush(stdout)
                        }
                        
                    case .thoughtCompleted:
                        print("\n")
                        
                    case .toolCall:
                        // Legacy or internal buffering
                        if let toolCalls = delta.toolCalls {
                            for call in toolCalls {
                                let index = call.index
                                var state = toolCallState[index] ?? ("", "")
                                if let name = call.name { state.name += name }
                                if let args = call.arguments { state.args += args }
                                toolCallState[index] = state
                            }
                        }
                        
                    case .toolCallError:
                        if let err = delta.toolCallError {
                            print(TerminalUI.red("❌ Tool Error (\(err.name)): \(err.error)"))
                        }
                        
                    case .toolExecution:
                        if let execution = delta.toolExecution {
                            switch execution.status {
                            case "attempting":
                                let targetInfo = execution.target != nil ? " on \(execution.target!)" : ""
                                print(TerminalUI.yellow("🔄 Running \(execution.name ?? "tool")\(targetInfo)..."))
                            case "success":
                                print(TerminalUI.green("✅ Tool completed"))
                            case "failure":
                                print(TerminalUI.red("❌ Tool failed: \(execution.result ?? "Unknown error")"))
                            default:
                                break
                            }
                        }
                        
                    case .delta:
                        if let content = delta.content {
                            if !assistantStartPrinted {
                                TerminalUI.printAssistantStart()
                                assistantStartPrinted = true
                            }
                            print(content, terminator: "")
                            fflush(stdout)
                        }
                        
                    case .generationCompleted:
                        if let meta = delta.responseMetadata {
                            if let snapshotData = meta.debugSnapshotData {
                                await updateDebugSnapshot(snapshotData)
                            }

                            let tokens = meta.totalTokens ?? 0
                            let dur = String(format: "%.1fs", meta.duration ?? 0)
                            print(TerminalUI.dim("\n[Generated in \(dur), \(tokens) tokens]"))
                        } else {
                            print("\n")
                        }
                        
                    case .generationCancelled:
                        print(TerminalUI.yellow("\n[Generation cancelled]"))

                    case .error:
                        if let error = delta.error {
                            print("\n")
                            TerminalUI.printError("Stream Error: \(error)")
                            return
                        }
                        
                    case .streamCompleted:
                        break
                    }
                }

            } catch {
                if !(error is CancellationError) {
                    print("")
                    await handleError(error)
                }
            }
        }
        await currentGenerationTask?.value
        currentGenerationTask = nil
    }

    private func updateDebugSnapshot(_ data: Data) {
        self.lastDebugSnapshot = try? SerializationUtils.jsonDecoder.decode(DebugSnapshot.self, from: data)
    }

    // MARK: - ChatREPLController Protocol

    func stop() async {
        running = false
    }

    func switchSession(_ session: Session) async {
        self.session = session
        self.selectedWorkspaceId = nil
        LocalConfigManager.shared.updateLastSessionId(session.id.uuidString)
        TerminalUI.printInfo("Switched to session \(session.id.uuidString.prefix(8))")
        await showContext()
        await checkAndRestoreWorkspaces()
    }

    func setSelectedWorkspace(_ id: UUID?) async {
        self.selectedWorkspaceId = id
    }

    public func getSelectedWorkspace() -> UUID? {
        return selectedWorkspaceId
    }

    public func getLastDebugSnapshot() -> DebugSnapshot? {
        return lastDebugSnapshot
    }

    func refreshContext() async {
        await showContext()
    }

    private func checkAndRestoreWorkspaces() async {
        do {
            let sessionWS = try await client.listSessionWorkspaces(sessionId: session.id)
            var workspacesToRestore: [WorkspaceReference] = []

            // Check Primary (Server)
            if let primary = sessionWS.primary, primary.status == .missing, primary.hostType == .server {
                workspacesToRestore.append(primary)
            }

            // Check Attached (Client)
            // Get my identity
            if let identity = RegistrationManager.shared.getIdentity() {
                for ws in sessionWS.attached {
                    if ws.hostType == .client, ws.ownerId == identity.clientId {
                         // Check local existence
                         // URI format: file://hostname/path
                         if let url = URL(string: ws.uri.description), url.host == identity.hostname {
                             let path = url.path
                             if !FileManager.default.fileExists(atPath: path) {
                                 workspacesToRestore.append(ws)
                             } else {
                                 // Add active ones to local tracking if they exist
                                 LocalConfigManager.shared.saveClientWorkspace(uri: ws.uri.description, id: ws.id.uuidString)
                             }
                         }
                    }
                }
            }

            if !workspacesToRestore.isEmpty {
                print(TerminalUI.dim("------------------------------------------------"))
                TerminalUI.printWarning("Missing Workspaces Detected:")
                for ws in workspacesToRestore {
                    print(" - \(ws.uri.description) (\(ws.hostType == .server ? "Server" : "Client"))")
                }
                print("")
                print("Do you want to restore these workspaces? [y/N] ", terminator: "")
                fflush(stdout)

                if let input = lineReader.readLine(prompt: "", completion: nil)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), input == "y" {
                    for ws in workspacesToRestore {
                        if ws.hostType == .server {
                            try await client.restoreWorkspace(sessionId: session.id, workspaceId: ws.id)
                            TerminalUI.printSuccess("Restored server workspace: \(ws.uri.description)")
                        } else {
                            // Client workspace
                             if let url = URL(string: ws.uri.description) {
                                 try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                 TerminalUI.printSuccess("Created local directory: \(url.path)")
                             }
                        }
                    }
                } else {
                     print("Skipping restoration.")
                }
                print(TerminalUI.dim("------------------------------------------------"))
                print("")
            }

        } catch {
            // Ignore errors here to not block startup
        }
    }

    // MARK: - Internal Logic

    private func readInput() async -> String? {
        print("")
        
        // Fetch context summary
        let contextSummary = await getContextSummary()
        if !contextSummary.isEmpty {
            print(TerminalUI.dim(contextSummary))
        }

        var wsName: String? = nil
        if let selectedId = selectedWorkspaceId {
            wsName = (try? await client.getWorkspace(selectedId))?.uri.description
        }

        let prompt = TerminalUI.getPromptString(workspace: wsName)

        // Prepare completion handler
        let commandNames = await registry.allCommands.map { "/" + $0.name }
        let aliases = await registry.allCommands.flatMap { cmd in cmd.aliases.map { "/" + $0 } }
        let allCandidates = (commandNames + aliases).sorted()

        // Use LineReader for vi-style editing and autocomplete
        guard
            let line = lineReader.readLine(
                prompt: prompt,
                completion: { text in
                    guard text.hasPrefix("/") else { return [] }
                    return allCandidates.filter { $0.hasPrefix(text) }
                })
        else {
            running = false
            return nil
        }

        return line
    }

    private func getContextSummary() async -> String {
        do {
            // Workspaces
            let sessionWS = try await client.listSessionWorkspaces(sessionId: session.id)
            var wsSummary = "No Workspace"

            let displayId = selectedWorkspaceId ?? sessionWS.primary?.id

            if let targetId = displayId {
                let ws = try await client.getWorkspace(targetId)
                let icon = selectedWorkspaceId == nil ? "📂" : "🎯"
                wsSummary = "\(icon) \(ws.uri.description)"

                if selectedWorkspaceId == nil && !sessionWS.attached.isEmpty {
                    wsSummary += " (+\(sessionWS.attached.count) attached)"
                }
            }

            // Memories count if easy
            let config = try await client.getConfiguration()
            let memories = try await client.listMemories()
            let activeCount = min(memories.count, config.memoryContextLimit)

            return "\(wsSummary) | 🧠 \(activeCount) active memories"
        } catch {
            return TerminalUI.yellow("⚠️ Context unavailable")
        }
    }

    private func showContext() async {
        do {
            let memories = try await client.listMemories()
            let config = try await client.getConfiguration()

            if !memories.isEmpty || config.documentContextLimit > 0 {
                print(TerminalUI.dim("─────────────────────────────────────────"))

                if !memories.isEmpty {
                    let limit = config.memoryContextLimit
                    let activeCount = min(memories.count, limit)
                    print(
                        TerminalUI.dim(
                            "📚 \(activeCount) memories active (of \(memories.count) total)"))
                }

                if config.documentContextLimit > 0 {
                    print(TerminalUI.dim("📄 Document context: \(config.documentContextLimit) max"))
                }

                print(TerminalUI.dim("─────────────────────────────────────────"))
                print("")
            }
        } catch {
            TerminalUI.printWarning("Could not load context: \(error.localizedDescription)")
        }
    }

    private func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmdName = parts.first.map(String.init) else { return }

        let args = commandLine.split(separator: " ", omittingEmptySubsequences: true).map(
            String.init)

        // Find command
        // registry.getCommand handles aliases and prefix stripping
        if let command = await registry.getCommand(cmdName) {

            // Context construction
            // We pass 'self' as the controller. BUT 'self' is actor.
            // SlashCommand run is async.
            // Protocol defines 'ChatContext' struct which holds 'ChatREPLController'.
            // ChatREPLController is protocol, and 'self' conforms to it.
            // But strict concurrency might complain about passing isolated actor 'self' as protocol existentially if not Sendable.
            // ChatREPLController is Sendable. Actor type is Sendable.

            let context = ChatContext(
                client: client, session: session, output: StandardOutput(), repl: self)

            do {
                try await command.run(args: Array(args.dropFirst()), context: context)
            } catch {
                await handleError(error)
            }
        } else {
            TerminalUI.printError("Unknown command: \(cmdName). Type /help for available commands.")
        }
    }

    private func handleError(_ error: Error) async {
        if let clientError = error as? MonadClientError {
            switch clientError {
            case .unauthorized:
                TerminalUI.printError("Unauthorized. Please check your API key or configuration.")
            case .serverNotReachable:
                TerminalUI.printError("Server not reachable. Please ensure the server is running.")
            case .notFound:
                TerminalUI.printError("Resource not found.")
            case .httpError(let statusCode, let message):
                TerminalUI.printError("HTTP Error \(statusCode): \(message ?? "Unknown")")
            case .networkError(let err):
                TerminalUI.printError("Network Error: \(err.localizedDescription)")
            case .decodingError(let err):
                TerminalUI.printError("Decoding Error: \(err.localizedDescription)")
            case .invalidURL:
                 TerminalUI.printError("Invalid URL.")
            case .unknown(let msg):
                TerminalUI.printError("Error: \(msg)")
            }
        } else {
            TerminalUI.printError("Error: \(error.localizedDescription)")
        }
    }
}