import Foundation
import MonadClient

// MARK: - Core Commands

struct HelpCommand: SlashCommand {
    let name = "help"
    let aliases = ["h", "?"]
    let description = "Show available commands"
    let category: String? = "Chat Commands"
    let registry: SlashCommandRegistry

    func run(args: [String], context: ChatContext) async throws {
        let commands = await registry.allCommands

        // Group by category
        var grouped: [String: [SlashCommand]] = [:]
        for cmd in commands {
            let cat = cmd.category ?? "General"
            grouped[cat, default: []].append(cmd)
        }

        let sortedCategories = grouped.keys.sorted {
            // "General" first/last? Let's generic sort, but maybe put General first or last.
            // Let's use specific order if possible, or just strict alphabetical.
            // Custom order: Core/General, Chat, Filesystem, Tools, Data, CONFIG
            if $0 == "General" { return true }
            if $1 == "General" { return false }
            return $0 < $1
        }

        print("\n" + TerminalUI.bold("Available Commands:") + "\n")

        for cat in sortedCategories {
            guard let cmds = grouped[cat], !cmds.isEmpty else { continue }
            print(TerminalUI.bold(cat) + ":")

            for cmd in cmds {
                let aliasesStr =
                    cmd.aliases.isEmpty ? "" : " (\(cmd.aliases.joined(separator: ", ")))"
                let namePart = "/\(cmd.name)\(aliasesStr)".padding(
                    toLength: 30, withPad: " ", startingAt: 0)
                print("  \(TerminalUI.cyan(namePart)) \(cmd.description)")
            }
            print("")
        }
    }
}

struct QuitCommand: SlashCommand {
    let name = "quit"
    let aliases = ["q", "exit"]
    let description = "Exit the chat"
    let category: String? = "Chat Commands"

    func run(args: [String], context: ChatContext) async throws {
        await context.repl.stop()
        TerminalUI.printInfo("Goodbye!")
    }
}

struct NewSessionCommand: SlashCommand {
    let name = "new"
    let description = "Start a new chat session"
    let category: String? = "Session Management"

    func run(args: [String], context: ChatContext) async throws {
        do {
            let session = try await context.client.createSession()
            await context.repl.switchSession(session)
            TerminalUI.printSuccess("Started new session \(session.id.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to create session: \(error.localizedDescription)")
        }
    }
}

// MARK: - Specialized Commands

struct SessionCommand: SlashCommand {
    let name = "session"
    let aliases = ["sessions"]
    let description = "Manage sessions"
    let category: String? = "Session Management"
    let usage = "/session [list|delete|rename|switch|log] [args]"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"

        switch subcommand {
        case "list", "ls":
            try await listSessions(context: context)
        case "delete", "rm":
            if args.count > 1 {
                try await deleteSession(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /session delete <session-id>")
            }
        case "rename", "name":
            if args.count > 1 {
                let newTitle = args.dropFirst().joined(separator: " ")
                try await renameSession(newTitle, context: context)
            } else {
                TerminalUI.printError("Usage: /session rename <new-name>")
            }
        case "switch", "use":
            if args.count > 1 {
                try await switchSession(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /session switch <session-id-prefix>")
            }
        case "log", "history":
            try await showHistory(context: context)
        default:
            try await listSessions(context: context)
        }
    }

    private func showHistory(context: ChatContext) async throws {
        let messages = try await context.client.getHistory(sessionId: context.session.id)
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
    }

    private func listSessions(context: ChatContext) async throws {
        let sessions = try await context.client.listSessions()
        if sessions.isEmpty {
            TerminalUI.printInfo("No sessions found.")
            return
        }

        print("\n" + TerminalUI.bold("Sessions:") + "\n")
        let currentId = context.session.id

        for s in sessions {
            let title = s.title ?? "Untitled"
            let dateStr = TerminalUI.formatDate(s.createdAt)
            let isCurrent = s.id == currentId
            let marker = isCurrent ? TerminalUI.green(" ●") : ""
            let idStr = s.id.uuidString.prefix(8)

            print(
                "  \(TerminalUI.dim(String(idStr)))  \(title)  \(TerminalUI.dim(dateStr))\(marker)")
        }
        print("")
    }

    private func deleteSession(_ idStr: String, context: ChatContext) async throws {
        if let uuid = UUID(uuidString: idStr) {
            try await context.client.deleteSession(uuid)
            TerminalUI.printSuccess("Deleted session \(uuid.uuidString.prefix(8))")
            return
        }

        // Partial match
        let sessions = try await context.client.listSessions()
        if let match = sessions.first(where: {
            $0.id.uuidString.hasPrefix(idStr) || $0.id.uuidString.hasPrefix(idStr.uppercased())
        }) {
            try await context.client.deleteSession(match.id)
            TerminalUI.printSuccess("Deleted session \(match.id.uuidString.prefix(8))")
        } else {
            TerminalUI.printError("Invalid session ID or no match: \(idStr)")
        }
    }

    private func renameSession(_ title: String, context: ChatContext) async throws {
        try await context.client.updateSessionTitle(title, sessionId: context.session.id)
        TerminalUI.printSuccess("Renamed session to: \(title)")
    }

    private func switchSession(_ idStr: String, context: ChatContext) async throws {
        let sessions = try await context.client.listSessions()
        if let match = sessions.first(where: { $0.id.uuidString.hasPrefix(idStr) }) {
            await context.repl.switchSession(match)
            TerminalUI.printSuccess("Switched to session: \(match.title ?? match.id.uuidString)")
        } else {
            TerminalUI.printError("No session found matching: \(idStr)")
        }
    }
}
