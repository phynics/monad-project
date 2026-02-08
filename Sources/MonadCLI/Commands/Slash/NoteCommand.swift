import Foundation
import MonadClient

struct NoteCommand: SlashCommand {
    let name = "note"
    let aliases = ["notes"]
    let description = "Manage session notes"
    let category: String? = "Tools & Environment"
    let usage = "/note [list|create|read|delete] <args>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            try await listNotes(context: context)
        case "create", "new", "add":
            if args.count > 1 {
                try await createNote(args: Array(args.dropFirst()), context: context)
            } else {
                TerminalUI.printError("Usage: /note create <title>")
            }
        case "read", "show", "cat":
            if args.count > 1 {
                try await readNote(title: args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /note read <title>")
            }
        case "delete", "rm":
            if args.count > 1 {
                try await deleteNote(title: args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /note delete <title>")
            }
        default:
            try await listNotes(context: context)
        }
    }

    private func listNotes(context: ChatContext) async throws {
        let notes = try await context.client.listNotes(sessionId: context.session.id)
        if notes.isEmpty {
            TerminalUI.printInfo("No notes found in this session.")
            return
        }

        print("\n\(TerminalUI.bold("Session Notes:"))\n")
        for note in notes {
            print("  📝 \(TerminalUI.bold(note.name))")
        }
        print("")
    }

    private func createNote(args: [String], context: ChatContext) async throws {
        let title = args[0]

        print("Enter content for '\(title)' (end with empty line):")
        var content = ""
        while let line = readLine() {
            if line.isEmpty { break }
            content += line + "\n"
        }

        _ = try await context.client.createNote(sessionId: context.session.id, title: title, content: content)
        TerminalUI.printSuccess("Note '\(title)' created.")
    }

    private func readNote(title: String, context: ChatContext) async throws {
        let note = try await context.client.getNote(sessionId: context.session.id, title: title)
        print("\n\(TerminalUI.bold(note.name))\n")
        print(TerminalUI.renderMarkdown(note.content))
        print("")
    }

    private func deleteNote(title: String, context: ChatContext) async throws {
        try await context.client.deleteNote(sessionId: context.session.id, title: title)
        TerminalUI.printSuccess("Note '\(title)' deleted.")
    }
}
