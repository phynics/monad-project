import Foundation
import MonadClient

extension ChatREPL {
    func run() async throws {
        setupSignalHandler()
        await registerCommands()
        await showContext()
        await checkAndRestoreWorkspaces()

        while running {
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

            if trimmed.hasPrefix("/") {
                await handleSlashCommand(trimmed)
                continue
            }

            await sendMessage(trimmed)
        }
    }

    func readInput() async -> String? {
        print("")

        let contextSummary = await getContextSummary()
        if !contextSummary.isEmpty {
            print(TerminalUI.dim(contextSummary))
        }

        var wsName: String?
        if let selectedId = selectedWorkspaceId {
            wsName = (try? await client.workspace.getWorkspace(selectedId))?.uri.description
        }

        let prompt = TerminalUI.getPromptString(workspace: wsName)

        let commandNames = await registry.allCommands.map { "/" + $0.name }
        let aliases = await registry.allCommands.flatMap { cmd in cmd.aliases.map { "/" + $0 } }
        let allCandidates = (commandNames + aliases).sorted()

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

    func handleSlashCommand(_ commandLine: String) async {
        let parts = commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmdName = parts.first.map(String.init) else { return }

        let args = commandLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        if let command = await registry.getCommand(cmdName) {
            let context = ChatContext(
                client: client, session: session, output: StandardOutput(), repl: self
            )

            do {
                try await command.run(args: Array(args.dropFirst()), context: context)
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

    func registerCommands() async {
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
}
