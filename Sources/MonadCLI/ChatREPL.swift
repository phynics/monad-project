import Foundation
import MonadClient
import MonadShared

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
    private var signalSource: DispatchSourceSignal?

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

    /// Track consecutive Ctrl-C presses for force-exit
    private var lastSigintTime: Date?

    private func setupSignalHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleSigint()
            }
        }
        source.resume()
        signalSource = source
        // Ignore SIGINT in the main process to prevent it from killing us
        signal(SIGINT, SIG_IGN)
    }

    private func handleSigint() async {
        let now = Date()
        let isDoubleTap: Bool
        if let last = lastSigintTime, now.timeIntervalSince(last) < 1.0 {
            isDoubleTap = true
        } else {
            isDoubleTap = false
        }
        lastSigintTime = now

        if isDoubleTap {
            // Double Ctrl-C always exits
            TerminalUI.printInfo("\n\nGoodbye!")
            running = false
            exit(0)
        }

        if currentGenerationTask != nil {
            // Cancel the in-progress generation
            await cancelCurrentGeneration()
        } else {
            // No active generation — exit the REPL
            print("")
            TerminalUI.printInfo("Goodbye! (Press Ctrl-C again to force quit)")
            running = false
            exit(0)
        }
    }

    func cancelCurrentGeneration() async {
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

                var assistantStartPrinted = false
                // Accumulate streamed argument JSON fragments per toolCallId for display
                var toolCallArgs: [String: String] = [:]

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case let .meta(meta):
                        switch meta {
                        case let .generationContext(metadata):
                            if !metadata.memories.isEmpty || !metadata.files.isEmpty {
                                let memories = metadata.memories.count
                                let files = metadata.files.count
                                print(TerminalUI.dim("Using \(memories) memories and \(files) files"))
                            }
                        case .generationCompleted:
                            break
                        }

                    case let .delta(delta):
                        switch delta {
                        case let .thinking(thought):
                            if !assistantStartPrinted {
                                print(TerminalUI.dim("🤔 Thinking..."))
                                assistantStartPrinted = true
                            }
                            print(TerminalUI.dim(thought), terminator: "")
                            fflush(stdout)

                        case let .generation(content):
                            if !assistantStartPrinted {
                                TerminalUI.printAssistantStart()
                                assistantStartPrinted = true
                            }
                            print(content, terminator: "")
                            fflush(stdout)

                        case let .toolCall(delta):
                            // Accumulate argument JSON fragments so we can display them on execution
                            if let callId = delta.id {
                                toolCallArgs[callId] = (toolCallArgs[callId] ?? "") + (delta.arguments ?? "")
                            }

                        case let .toolExecution(toolCallId, status):
                            switch status {
                            case let .attempting(name, ref):
                                // End any in-progress streaming line before the tool block
                                if assistantStartPrinted { print("") }
                                assistantStartPrinted = false
                                let args = toolCallArgs[toolCallId] ?? ""
                                printToolAttempt(name: name, argsJSON: args, reference: ref)
                            default:
                                break
                            }
                        }

                    case let .error(err):
                        switch err {
                        case let .toolCallError(_, name, error):
                            print(TerminalUI.red("  ✗ Tool Error (\(name)): \(error)"))
                        case let .error(message):
                            print("\n")
                            TerminalUI.printError("Stream Error: \(message)")
                            return
                        case .cancelled:
                            print(TerminalUI.yellow("\n[Generation cancelled]"))
                        }

                    case let .completion(completion):
                        switch completion {
                        case let .generationCompleted(_, meta):
                            if let snapshotData = meta.debugSnapshotData {
                                updateDebugSnapshot(snapshotData)
                            }
                            let tokens = meta.totalTokens ?? 0
                            let dur = String(format: "%.1fs", meta.duration ?? 0)
                            print(TerminalUI.dim("\n[Generated in \(dur), \(tokens) tokens]"))

                        case let .toolExecution(_, status):
                            switch status {
                            case let .success(result):
                                printToolResult(result.output)
                            case let .failed(_, error):
                                print(TerminalUI.red("  ✗ \(error)"))
                            case let .failure(error):
                                print(TerminalUI.red("  ✗ \(error)"))
                            default:
                                break
                            }

                        case .streamCompleted:
                            break
                        }
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

    // MARK: - Tool Display Helpers

    private func printToolAttempt(name: String, argsJSON: String, reference: ToolReference) {
        let location: String
        switch reference {
        case .known: location = "server"
        case .custom: location = "local"
        }
        let paramsStr = formatToolArgs(argsJSON)
        let header = TerminalUI.blue("⟩ \(name)")
        let params = paramsStr.isEmpty ? "" : "  " + TerminalUI.dim(paramsStr)
        let loc = "  " + TerminalUI.dim("[\(location)]")
        print(header + params + loc)
    }

    private func printToolResult(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print(TerminalUI.dim("  ✓ (no output)"))
            return
        }
        let lines = trimmed.components(separatedBy: .newlines)
        let maxLines = 8
        for line in lines.prefix(maxLines) {
            let display = line.count > 120 ? String(line.prefix(120)) + "…" : line
            print(TerminalUI.dim("  \(display)"))
        }
        if lines.count > maxLines {
            print(TerminalUI.dim("  ↳ +\(lines.count - maxLines) more lines"))
        }
    }

    private func formatToolArgs(_ json: String) -> String {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !dict.isEmpty
        else { return "" }
        let parts = dict.keys.sorted().map { key -> String in
            let value = String(describing: dict[key]!)
            let truncated = value.count > 60 ? String(value.prefix(60)) + "…" : value
            return "\(key)=\(truncated)"
        }
        let joined = parts.joined(separator: "  ")
        return joined.count > 120 ? String(joined.prefix(120)) + "…" : joined
    }

    private func updateDebugSnapshot(_ data: Data) {
        lastDebugSnapshot = try? SerializationUtils.jsonDecoder.decode(DebugSnapshot.self, from: data)
    }

    // MARK: - ChatREPLController Protocol

    func stop() async {
        running = false
    }

    func switchSession(_ session: Session) async {
        self.session = session
        selectedWorkspaceId = nil
        LocalConfigManager.shared.updateLastSessionId(session.id.uuidString)
        TerminalUI.printInfo("Switched to session \(session.id.uuidString.prefix(8))")
        await showContext()
        await checkAndRestoreWorkspaces()
    }

    func setSelectedWorkspace(_ id: UUID?) async {
        selectedWorkspaceId = id
    }

    func getSelectedWorkspace() -> UUID? {
        return selectedWorkspaceId
    }

    func getLastDebugSnapshot() -> DebugSnapshot? {
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

        var wsName: String?
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
                }
            )
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

            print(TerminalUI.dim("─────────────────────────────────────────"))

            // Models
            let providerName = config.activeProvider.rawValue
            print(TerminalUI.dim("🤖 Provider: \(providerName)"))
            print(TerminalUI.dim("   Main:    \(config.modelName)"))
            if !config.utilityModel.isEmpty {
                print(TerminalUI.dim("   Utility: \(config.utilityModel)"))
            }
            if !config.fastModel.isEmpty, config.fastModel != config.utilityModel {
                print(TerminalUI.dim("   Fast:    \(config.fastModel)"))
            }

            if !memories.isEmpty {
                let limit = config.memoryContextLimit
                let activeCount = min(memories.count, limit)
                print(
                    TerminalUI.dim(
                        "📚 \(activeCount) memories active (of \(memories.count) total)"
                    )
                )
            }

            if config.documentContextLimit > 0 {
                print(TerminalUI.dim("📄 Document context: \(config.documentContextLimit) max"))
            }

            print(TerminalUI.dim("─────────────────────────────────────────"))
            print("")
        } catch {
            TerminalUI.printWarning("Could not load context: \(error.localizedDescription)")
        }
    }

    private func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmdName = parts.first.map(String.init) else { return }

        let args = commandLine.split(separator: " ", omittingEmptySubsequences: true).map(
            String.init
        )

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
                client: client, session: session, output: StandardOutput(), repl: self
            )

            do {
                try await command.run(args: Array(args.dropFirst()), context: context)
                // If it was a config command, we might want to refresh startup info?
                if command.name == "config" {
                    await showContext()
                }
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
            case let .httpError(statusCode, message):
                TerminalUI.printError("HTTP Error \(statusCode): \(message ?? "Unknown")")
            case let .networkError(err):
                TerminalUI.printError("Network Error: \(err.localizedDescription)")
            case let .decodingError(err):
                TerminalUI.printError("Decoding Error: \(err.localizedDescription)")
            case .invalidURL:
                TerminalUI.printError("Invalid URL.")
            case let .unknown(msg):
                TerminalUI.printError("Error: \(msg)")
            }
        } else {
            TerminalUI.printError("Error: \(error.localizedDescription)")
        }
    }
}
