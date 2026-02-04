import Foundation
import MonadClient

// MARK: - Chat REPL

actor ChatREPL {
    private let client: MonadClient
    private var session: Session
    private var running = true

    init(client: MonadClient, session: Session) {
        self.client = client
        self.session = session
    }

    func run() async throws {
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

    private func readInput() async -> String? {
        TerminalUI.printPrompt()

        // Use readline for vi-style editing
        guard let line = readLine() else {
            running = false
            return nil
        }

        return line
    }

    // MARK: - Slash Commands

    private func handleSlashCommand(_ command: String) async {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return }
        let cmd = String(first).lowercased()
        let args = Array(parts.dropFirst()).map { String($0) }

        switch cmd {
        case "/help", "/h", "/?":
            printHelp()

        case "/new":
            await startNewSession()

        case "/history":
            await showHistory()

        case "/config":
            await handleConfig(args)

        case "/sessions", "/session":
            await handleSessions(args)

        case "/memories", "/memory":
            await handleMemories(args)

        case "/notes", "/note":
            await handleNotes(args)

        case "/tools", "/tool":
            await handleTools(args)

        case "/workspaces", "/workspace":
            await handleWorkspaces(args)

        case "/quit", "/q", "/exit":
            running = false
            TerminalUI.printInfo("Goodbye!")

        default:
            TerminalUI.printError("Unknown command: \(cmd). Type /help for available commands.")
        }
    }

    private func printHelp() {
        print(
            """

            \(TerminalUI.bold("Chat Commands:"))
              /help, /h             Show this help message
              /new                  Start a new chat session
              /history              Show conversation history
              /quit, /q, /exit      Exit the chat

            \(TerminalUI.bold("Configuration:"))
              /config               Edit configuration (interactive)
              /config show          View current settings
              /config provider <n>  Switch provider

            \(TerminalUI.bold("Data Management:"))
              /sessions             List all sessions
              /session delete <id>  Delete a session
              /memories             List memories
              /memory search <q>    Search memories
              /notes                List notes
              /note add <title>     Create a note
              /workspaces           List/manage workspaces
              /tools                List available tools

            \(TerminalUI.bold("Tips:"))
              • Press Ctrl+C to cancel current generation
              • Press Ctrl+D to exit

            """)
    }

    // MARK: - Context Display

    private func showContext() async {
        do {
            // Fetch memories and show summary
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

                // Note: Documents would need a separate API endpoint
                // For now just show the limit from config
                if config.documentContextLimit > 0 {
                    print(TerminalUI.dim("📄 Document context: \(config.documentContextLimit) max"))
                }

                print(TerminalUI.dim("─────────────────────────────────────────"))
                print("")
            }
        } catch {
            // Silently fail - context display is optional
        }
    }

    // MARK: - Session Management

    private func startNewSession() async {
        do {
            session = try await client.createSession()
            TerminalUI.printInfo("Started new session \(session.id.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to create session: \(error.localizedDescription)")
        }
    }

    private func showHistory() async {
        do {
            let messages = try await client.getHistory(sessionId: session.id)

            if messages.isEmpty {
                TerminalUI.printInfo("No messages in this session yet.")
                return
            }

            print("")
            for message in messages {
                switch message.role {
                case .user:
                    print("\(TerminalUI.userColor("You:"))")
                    print(message.content)
                case .assistant:
                    print("\(TerminalUI.assistantColor("Assistant:"))")
                    print(message.content)
                case .system:
                    print("\(TerminalUI.systemColor("System:"))")
                    print(message.content)
                case .tool:
                    print("\(TerminalUI.toolColor("Tool:"))")
                    print(message.content)
                case .summary:
                    print("\(TerminalUI.dim("Summary:"))")
                    print(message.content)
                }
                print("")
            }
        } catch {
            TerminalUI.printError("Failed to fetch history: \(error.localizedDescription)")
        }
    }

    private func handleSessions(_ args: [String]) async {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            await listSessions()
        case "delete", "rm":
            if args.count > 1 {
                await deleteSession(args[1])
            } else {
                TerminalUI.printError("Usage: /session delete <session-id>")
            }
        default:
            await listSessions()
        }
    }

    private func listSessions() async {
        do {
            let sessions = try await client.listSessions()

            if sessions.isEmpty {
                TerminalUI.printInfo("No sessions found.")
                return
            }

            print("")
            print(TerminalUI.bold("Sessions:"))
            print("")

            for s in sessions {
                let title = s.title ?? "Untitled"
                let dateStr = TerminalUI.formatDate(s.createdAt)
                let current = s.id == session.id ? TerminalUI.green(" ●") : ""
                print(
                    "  \(TerminalUI.dim(s.id.uuidString.prefix(8).description))  \(title)  \(TerminalUI.dim(dateStr))\(current)"
                )
            }
            print("")
        } catch {
            TerminalUI.printError("Failed to list sessions: \(error.localizedDescription)")
        }
    }

    private func deleteSession(_ sessionId: String) async {
        guard let uuid = UUID(uuidString: sessionId) else {
            // Try partial match
            do {
                let sessions = try await client.listSessions()
                if let match = sessions.first(where: {
                    $0.id.uuidString.hasPrefix(sessionId.uppercased())
                }) {
                    await deleteSessionById(match.id)
                } else {
                    TerminalUI.printError("Invalid session ID: \(sessionId)")
                }
            } catch {
                TerminalUI.printError("Failed to find session: \(error.localizedDescription)")
            }
            return
        }
        await deleteSessionById(uuid)
    }

    private func deleteSessionById(_ uuid: UUID) async {
        do {
            try await client.deleteSession(uuid)
            TerminalUI.printSuccess("Deleted session \(uuid.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to delete session: \(error.localizedDescription)")
        }
    }

    // MARK: - Configuration

    private func handleConfig(_ args: [String]) async {
        guard let subcommand = args.first else {
            // No subcommand: open interactive editor
            await interactiveConfigEdit()
            return
        }

        switch subcommand {
        case "show", "view":
            await showConfig()
        case "set":
            if args.count >= 3 {
                await setConfig(key: args[1], value: args.dropFirst(2).joined(separator: " "))
            } else if args.count == 2 {
                await setConfigWithPrompt(key: args[1])
            } else {
                printConfigHelp()
            }
        case "provider":
            if args.count > 1 {
                await setProvider(args[1])
            } else {
                TerminalUI.printError(
                    "Usage: /config provider <openai|openrouter|ollama|compatible>")
            }
        case "help":
            printConfigHelp()
        default:
            // Unknown subcommand, show help
            printConfigHelp()
        }
    }

    private func printConfigHelp() {
        print(
            """

            \(TerminalUI.bold("Config Commands:"))
              /config                   Show current configuration
              /config edit              Interactive configuration editor
              /config set <key> <value> Set a specific value
              /config set <key>         Prompt for value
              /config provider <name>   Switch provider

            \(TerminalUI.bold("Available Keys:"))
              api-key       API key for the provider
              model         Main model name
              utility       Utility model (for summaries, etc.)
              fast          Fast model (for quick responses)
              endpoint      API endpoint URL
              memory        Memory context limit (number)
              document      Document context limit (number)

            \(TerminalUI.bold("Examples:"))
              /config set model gpt-4o
              /config set api-key
              /config provider openrouter

            """)
    }

    private func interactiveConfigEdit() async {
        do {
            var config = try await client.getConfiguration()
            guard var providerConfig = config.providers[config.activeProvider] else {
                TerminalUI.printError("No provider configuration found")
                return
            }

            print("")
            print(TerminalUI.bold("Configuration Editor"))
            print(TerminalUI.dim("Press Enter to keep current value, or type new value"))
            print("")

            // Endpoint
            print("Endpoint [\(providerConfig.endpoint)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                providerConfig.endpoint = input
            }

            // API Key
            print("API Key [\(maskApiKey(providerConfig.apiKey))]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                providerConfig.apiKey = input
            }

            // Model
            print("Model [\(providerConfig.modelName)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                providerConfig.modelName = input
            }

            // Utility Model
            let utilityDisplay =
                providerConfig.utilityModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.utilityModel
            print("Utility Model [\(utilityDisplay)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                providerConfig.utilityModel = input
            }

            // Fast Model
            let fastDisplay =
                providerConfig.fastModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.fastModel
            print("Fast Model [\(fastDisplay)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                providerConfig.fastModel = input
            }

            // Memory Limit
            print("Memory Limit [\(config.memoryContextLimit)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                if let limit = Int(input) {
                    config.memoryContextLimit = limit
                }
            }

            // Document Limit
            print("Document Limit [\(config.documentContextLimit)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                if let limit = Int(input) {
                    config.documentContextLimit = limit
                }
            }

            // Save
            config.providers[config.activeProvider] = providerConfig
            try await client.updateConfiguration(config)
            print("")
            TerminalUI.printSuccess("Configuration updated!")

        } catch {
            TerminalUI.printError("Failed to update config: \(error.localizedDescription)")
        }
    }

    private func setConfigWithPrompt(key: String) async {
        print("Enter value for \(key): ", terminator: "")
        guard let value = readLine()?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            TerminalUI.printError("No value provided")
            return
        }
        await setConfig(key: key, value: value)
    }

    private func showConfig() async {
        do {
            let config = try await client.getConfiguration()

            print("")
            print(TerminalUI.bold("LLM Configuration"))
            print("")

            print("  \(TerminalUI.dim("Provider:"))     \(config.activeProvider.rawValue)")

            if let providerConfig = config.providers[config.activeProvider] {
                print("  \(TerminalUI.dim("Endpoint:"))     \(providerConfig.endpoint)")
                print("  \(TerminalUI.dim("API Key:"))      \(maskApiKey(providerConfig.apiKey))")
                print("  \(TerminalUI.dim("Model:"))        \(providerConfig.modelName)")
                print("  \(TerminalUI.dim("Utility:"))      \(providerConfig.utilityModel)")
                print("  \(TerminalUI.dim("Fast:"))         \(providerConfig.fastModel)")
                print("  \(TerminalUI.dim("Tool Format:"))  \(providerConfig.toolFormat.rawValue)")
            }

            print("")
            print("  \(TerminalUI.dim("Memory Limit:"))   \(config.memoryContextLimit)")
            print("  \(TerminalUI.dim("Document Limit:")) \(config.documentContextLimit)")
            print("")
            print("  \(TerminalUI.dim("Valid:"))          \(config.isValid ? "✓" : "✗")")
            print("")
        } catch {
            TerminalUI.printError("Failed to get configuration: \(error.localizedDescription)")
        }
    }

    private func maskApiKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func setConfig(key: String, value: String) async {
        do {
            var config = try await client.getConfiguration()

            switch key.lowercased() {
            case "api-key", "apikey", "key":
                config.apiKey = value
            case "model":
                config.modelName = value
            case "utility-model", "utility":
                config.utilityModel = value
            case "fast-model", "fast":
                config.fastModel = value
            case "endpoint", "url":
                config.endpoint = value
            case "memory-limit", "memory":
                if let limit = Int(value) {
                    config.memoryContextLimit = limit
                } else {
                    TerminalUI.printError("Invalid number: \(value)")
                    return
                }
            case "document-limit", "document":
                if let limit = Int(value) {
                    config.documentContextLimit = limit
                } else {
                    TerminalUI.printError("Invalid number: \(value)")
                    return
                }
            default:
                TerminalUI.printError("Unknown config key: \(key)")
                print(
                    "  Keys: api-key, model, utility-model, fast-model, endpoint, memory-limit, document-limit"
                )
                return
            }

            try await client.updateConfiguration(config)
            TerminalUI.printSuccess("Updated \(key) = \(key.contains("key") ? "***" : value)")
        } catch {
            TerminalUI.printError("Failed to update config: \(error.localizedDescription)")
        }
    }

    private func setProvider(_ name: String) async {
        let provider: LLMProvider
        switch name.lowercased() {
        case "openai":
            provider = .openAI
        case "openrouter":
            provider = .openRouter
        case "ollama":
            provider = .ollama
        case "compatible", "openai-compatible":
            provider = .openAICompatible
        default:
            TerminalUI.printError("Unknown provider: \(name)")
            print("  Available: openai, openrouter, ollama, compatible")
            return
        }

        do {
            var config = try await client.getConfiguration()
            config.activeProvider = provider
            try await client.updateConfiguration(config)
            TerminalUI.printSuccess("Switched to \(provider.rawValue)")
        } catch {
            TerminalUI.printError("Failed to switch provider: \(error.localizedDescription)")
        }
    }

    // MARK: - Memories

    private func handleMemories(_ args: [String]) async {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            await listMemories()
        case "search":
            if args.count > 1 {
                await searchMemories(args.dropFirst().joined(separator: " "))
            } else {
                TerminalUI.printError("Usage: /memory search <query>")
            }
        default:
            await listMemories()
        }
    }

    private func listMemories() async {
        do {
            let memories = try await client.listMemories()
            let config = try await client.getConfiguration()
            let activeLimit = config.memoryContextLimit

            if memories.isEmpty {
                TerminalUI.printInfo("No memories found.")
                return
            }

            print("")
            print(TerminalUI.bold("Memories:"))
            print(TerminalUI.dim("(\(min(memories.count, activeLimit)) active / \(memories.count) total)"))
            print("")

            for (index, memory) in memories.prefix(20).enumerated() {
                let isActive = index < activeLimit
                let status = isActive ? TerminalUI.green("●") : TerminalUI.dim("○")
                let dateStr = TerminalUI.formatDate(memory.createdAt)
                let preview = String(memory.content.prefix(50)).replacingOccurrences(
                    of: "\n", with: " ")
                print(
                    "  \(status) \(TerminalUI.dim(memory.id.uuidString.prefix(8).description))  \(preview)\(memory.content.count > 50 ? "..." : "")  \(TerminalUI.dim(dateStr))"
                )
            }

            if memories.count > 20 {
                print("  \(TerminalUI.dim("... and \(memories.count - 20) more"))")
            }
            print("")
        } catch {
            TerminalUI.printError("Failed to list memories: \(error.localizedDescription)")
        }
    }

    private func searchMemories(_ query: String) async {
        do {
            let memories = try await client.searchMemories(query, limit: 10)

            if memories.isEmpty {
                TerminalUI.printInfo("No memories found matching: \(query)")
                return
            }

            print("")
            print(TerminalUI.bold("Search Results:"))
            print("")

            for memory in memories {
                print(
                    "  \(TerminalUI.bold(String(memory.content.prefix(60))))\(memory.content.count > 60 ? "..." : "")"
                )
                if !memory.tagArray.isEmpty {
                    print("  \(TerminalUI.dim("Tags: \(memory.tagArray.joined(separator: ", "))"))")
                }
                print("")
            }
        } catch {
            TerminalUI.printError("Failed to search memories: \(error.localizedDescription)")
        }
    }

    // MARK: - Notes

    private func handleNotes(_ args: [String]) async {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            await listNotes()
        case "add", "create", "new":
            if args.count > 1 {
                let title = args.dropFirst().joined(separator: " ")
                await createNote(title: title)
            } else {
                TerminalUI.printError("Usage: /note add <title>")
            }
        default:
            await listNotes()
        }
    }

    private func listNotes() async {
        do {
            let notes = try await client.listNotes()

            if notes.isEmpty {
                TerminalUI.printInfo("No notes found.")
                return
            }

            print("")
            print(TerminalUI.bold("Notes:"))
            print("")

            for note in notes {
                let dateStr = TerminalUI.formatDate(note.updatedAt)
                print(
                    "  \(TerminalUI.dim(note.id.uuidString.prefix(8).description))  \(note.name)  \(TerminalUI.dim(dateStr))"
                )
            }
            print("")
        } catch {
            TerminalUI.printError("Failed to list notes: \(error.localizedDescription)")
        }
    }

    private func createNote(title: String) async {
        print("Enter note content (end with empty line):")
        var content = ""
        while let line = readLine() {
            if line.isEmpty { break }
            content += line + "\n"
        }

        do {
            let note = try await client.createNote(
                title: title, content: content.trimmingCharacters(in: .whitespacesAndNewlines))
            TerminalUI.printSuccess("Created note: \(note.id.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to create note: \(error.localizedDescription)")
        }
    }

    // MARK: - Tools

    private func handleTools(_ args: [String]) async {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            await listTools()
        case "enable":
            if args.count > 1 {
                await enableTool(args[1])
            } else {
                TerminalUI.printError("Usage: /tool enable <name>")
            }
        case "disable":
            if args.count > 1 {
                await disableTool(args[1])
            } else {
                TerminalUI.printError("Usage: /tool disable <name>")
            }
        default:
            await listTools()
        }
    }

    private func listTools() async {
        do {
            let tools = try await client.listTools()

            if tools.isEmpty {
                TerminalUI.printInfo("No tools available.")
                return
            }

            print("")
            print(TerminalUI.bold("Available Tools:"))
            print("")

            for tool in tools {
                let status = tool.isEnabled ? TerminalUI.green("●") : TerminalUI.dim("○")
                print("  \(status) \(TerminalUI.bold(tool.name))")
                print("    \(TerminalUI.dim(tool.description))")
            }
            print("")
        } catch {
            TerminalUI.printError("Failed to list tools: \(error.localizedDescription)")
        }
    }

    private func enableTool(_ name: String) async {
        do {
            try await client.enableTool(name)
            TerminalUI.printSuccess("Enabled tool: \(name)")
        } catch {
            TerminalUI.printError("Failed to enable tool: \(error.localizedDescription)")
        }
    }

    private func disableTool(_ name: String) async {
        do {
            try await client.disableTool(name)
            TerminalUI.printSuccess("Disabled tool: \(name)")
        } catch {
            TerminalUI.printError("Failed to disable tool: \(error.localizedDescription)")
        }
    }

    // MARK: - Workspaces

    private func handleWorkspaces(_ args: [String]) async {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            await listWorkspaces()
        case "attach":
            if args.count > 1 {
                await attachWorkspace(args[1])
            } else {
                TerminalUI.printError("Usage: /workspace attach <workspace-id>")
            }
        default:
            await listWorkspaces()
        }
    }

    private func listWorkspaces() async {
        do {
            let workspaces = try await client.listWorkspaces()
            let sessionWS = try await client.listSessionWorkspaces(sessionId: session.id)

            if workspaces.isEmpty {
                TerminalUI.printInfo("No workspaces found.")
                return
            }

            print("")
            print(TerminalUI.bold("Workspaces:"))
            print("")

            for ws in workspaces {
                let isPrimary = sessionWS.primary == ws.id
                let isAttached = sessionWS.attached.contains(ws.id)
                
                let marker = isPrimary ? TerminalUI.green(" ★") : (isAttached ? TerminalUI.blue(" ●") : " ○")
                let type = isPrimary ? " (Primary)" : (isAttached ? " (Attached)" : "")
                
                print("  \(marker) \(TerminalUI.bold(ws.uri.description))\(type)")
                print("     ID: \(TerminalUI.dim(ws.id.uuidString))")
                if let path = ws.rootPath {
                    print("     Path: \(path)")
                }
                print("")
            }
        } catch {
            TerminalUI.printError("Failed to list workspaces: \(error.localizedDescription)")
        }
    }

    private func attachWorkspace(_ workspaceId: String) async {
        guard let uuid = UUID(uuidString: workspaceId) else {
            // Try partial match by URI
            do {
                let workspaces = try await client.listWorkspaces()
                if let match = workspaces.first(where: { $0.uri.description.contains(workspaceId) }) {
                    await attachWorkspaceById(match.id)
                } else {
                    TerminalUI.printError("Invalid workspace ID or URI: \(workspaceId)")
                }
            } catch {
                TerminalUI.printError("Failed to find workspace: \(error.localizedDescription)")
            }
            return
        }
        await attachWorkspaceById(uuid)
    }

    private func attachWorkspaceById(_ uuid: UUID) async {
        do {
            try await client.attachWorkspace(uuid, to: session.id, isPrimary: false)
            TerminalUI.printSuccess("Attached workspace to current session.")
        } catch {
            TerminalUI.printError("Failed to attach workspace: \(error.localizedDescription)")
        }
    }

    // MARK: - Chat

    private func sendMessage(_ message: String) async {
        do {
            print("")
            TerminalUI.printAssistantStart()

            let stream = try await client.chatStream(sessionId: session.id, message: message)

            for try await delta in stream {
                if let content = delta.content {
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
