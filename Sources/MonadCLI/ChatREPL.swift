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

    // Slash Command Registry
    private let registry = SlashCommandRegistry()
    private let lineReader = LineReader()

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

        // File System
        await registry.register(LsCommand())
        await registry.register(CatCommand())
        await registry.register(RmCommand())
        await registry.register(WriteCommand())
        await registry.register(EditCommand())

        // Tools & Env
        await registry.register(ToolCommand())
        await registry.register(PersonaCommand())
        await registry.register(WorkspaceSlashCommand())
        await registry.register(MemoryCommand())
        await registry.register(PruneSlashCommand())
        await registry.register(TaskCommand())
        await registry.register(ClientCommand())
        await registry.register(JobSlashCommand())
    }

    func run() async throws {
        // Register commands first
        await registerCommands()

        // Ensure client is registered and intrinsic tools are active
        _ = try? await RegistrationManager.shared.ensureRegistered(client: client)

        // Show active context (memories, documents) at startup
        await showContext()

        while running {
            // Read input with vi-style editing via readline
            guard let input = await readInput() else {
                continue
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                continue
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

    // MARK: - ChatREPLController Protocol

    func stop() async {
        running = false
    }

    func switchSession(_ session: Session) async {
        self.session = session
        // Keeping selected workspace ID if compatible? Or reset?
        // Safest to reset or re-validate.
        // Let's reset for now to avoid confusion.
        self.selectedWorkspaceId = nil
        TerminalUI.printInfo("Switched to session \(session.id.uuidString.prefix(8))")
        await showContext()
    }

    func setSelectedWorkspace(_ id: UUID?) async {
        self.selectedWorkspaceId = id
    }

    func getSelectedWorkspace() async -> UUID? {
        return selectedWorkspaceId
    }

    func refreshContext() async {
        await showContext()
    }

    // MARK: - Internal Logic

    private func readInput() async -> String? {
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

            let displayId = selectedWorkspaceId ?? sessionWS.primary

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
            return ""
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
            // Silently fail
        }
    }

    private func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmdName = parts.first.map(String.init) else { return }

        // Parse args properly?
        // Logic for splitting args: "cmd arg1 arg2" -> ["cmd", "arg1", "arg2"]
        // Some commands might want full string.
        // SlashCommand protocol assumes [String].
        // Let's do simple space splitting for now as standard.
        // If commands need complex parsing they can rejoin.
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
                TerminalUI.printError("Command failed: \(error.localizedDescription)")
            }
        } else {
            TerminalUI.printError("Unknown command: \(cmdName). Type /help for available commands.")
        }
    }

    private func sendMessage(_ message: String) async {
        do {
            print("")
            TerminalUI.printAssistantStart()

            // Optimistic local echo or wait for stream?
            // Usually we wait for stream.

            let stream = try await client.chatStream(sessionId: session.id, message: message)

            var toolCallState: [Int: (name: String, args: String)] = [:]
            var currentToolIndex: Int? = nil

            for try await delta in stream {
                // 1. Metadata
                if let metadata = delta.metadata {
                    if !metadata.memories.isEmpty || !metadata.files.isEmpty {
                        let memories = metadata.memories.count
                        let files = metadata.files.count
                        print(TerminalUI.dim(" [Using \(memories) memories and \(files) files]"))
                        TerminalUI.printAssistantStart()  // Restart prompt line
                    }
                }

                // 2. Error
                if let error = delta.error {
                    print("\n")
                    TerminalUI.printError("Stream Error: \(error)")
                    return
                }

                // 3. Tool Calls
                if let toolCalls = delta.toolCalls {
                    for call in toolCalls {
                        let index = call.index
                        var state = toolCallState[index] ?? ("", "")
                        if let name = call.name { state.name += name }
                        if let args = call.arguments { state.args += args }
                        toolCallState[index] = state

                        if currentToolIndex != index {
                            if currentToolIndex != nil { print("") }
                            TerminalUI.printToolCall(name: state.name, args: state.args)
                            currentToolIndex = index
                        }
                    }
                    fflush(stdout)
                }

                // 4. Content
                if let content = delta.content {
                    if currentToolIndex != nil {
                        print("\n")
                        TerminalUI.printAssistantStart()
                        currentToolIndex = nil
                    }
                    print(content, terminator: "")
                    fflush(stdout)
                }
            }
            print("\n")

        } catch {
            print("")
            TerminalUI.printError("Error: \(error.localizedDescription)")
        }
    }
}
