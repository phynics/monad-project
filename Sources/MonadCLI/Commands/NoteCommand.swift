import ArgumentParser
import Foundation
import MonadClient

struct NoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Manage notes",
        subcommands: [List.self, Show.self, Create.self, Edit.self, Delete.self]
    )

    // MARK: - List

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all notes"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

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
                        "  \(TerminalUI.dim(note.id.uuidString.prefix(8).description))  \(note.title)  \(TerminalUI.dim(dateStr))"
                    )
                }
                print("")
            } catch {
                TerminalUI.printError("Failed to list notes: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Show

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show note content"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Note ID")
        var noteId: String

        func run() async throws {
            guard let uuid = UUID(uuidString: noteId) else {
                TerminalUI.printError("Invalid note ID: \(noteId)")
                throw ExitCode.failure
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                let note = try await client.getNote(uuid)

                print("")
                print(TerminalUI.bold(note.title))
                print(TerminalUI.dim("───────────────────────────────────"))
                print(note.content)
                print("")
                print(TerminalUI.dim("Created: \(TerminalUI.formatDate(note.createdAt))"))
                print(TerminalUI.dim("Updated: \(TerminalUI.formatDate(note.updatedAt))"))
                print("")
            } catch {
                TerminalUI.printError("Failed to show note: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Create

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new note"
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .shortAndLong, help: "Note title")
        var title: String

        @Option(name: .shortAndLong, help: "Note content (or pipe via stdin)")
        var content: String?

        @Flag(name: .shortAndLong, help: "Open editor to write content")
        var editor: Bool = false

        func run() async throws {
            let noteContent: String

            if let content = content {
                noteContent = content
            } else if editor {
                // Open editor
                guard let edited = openEditor(with: "") else {
                    TerminalUI.printError("Editor cancelled or failed")
                    throw ExitCode.failure
                }
                noteContent = edited
            } else {
                // Read from stdin
                TerminalUI.printInfo("Enter note content (Ctrl+D to finish):")
                var lines: [String] = []
                while let line = readLine() {
                    lines.append(line)
                }
                noteContent = lines.joined(separator: "\n")
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                let note = try await client.createNote(title: title, content: noteContent)
                print("Created note: \(note.id.uuidString)")
            } catch {
                TerminalUI.printError("Failed to create note: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func openEditor(with content: String) -> String? {
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
                "monad_note_\(UUID().uuidString).md")

            do {
                try content.write(to: tempFile, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [editor, tempFile.path]
                process.standardInput = FileHandle.standardInput
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    return nil
                }

                return try String(contentsOf: tempFile, encoding: .utf8)
            } catch {
                return nil
            }
        }
    }

    // MARK: - Edit

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Edit an existing note"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Note ID")
        var noteId: String

        func run() async throws {
            guard let uuid = UUID(uuidString: noteId) else {
                TerminalUI.printError("Invalid note ID: \(noteId)")
                throw ExitCode.failure
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                let note = try await client.getNote(uuid)

                // Open editor with existing content
                guard let edited = openEditor(with: note.content) else {
                    TerminalUI.printError("Editor cancelled or failed")
                    throw ExitCode.failure
                }

                _ = try await client.updateNote(uuid, content: edited)
                print("Updated note: \(noteId)")
            } catch {
                TerminalUI.printError("Failed to edit note: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func openEditor(with content: String) -> String? {
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
                "monad_note_\(UUID().uuidString).md")

            do {
                try content.write(to: tempFile, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [editor, tempFile.path]
                process.standardInput = FileHandle.standardInput
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    return nil
                }

                return try String(contentsOf: tempFile, encoding: .utf8)
            } catch {
                return nil
            }
        }
    }

    // MARK: - Delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a note"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Note ID")
        var noteId: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var force: Bool = false

        func run() async throws {
            guard let uuid = UUID(uuidString: noteId) else {
                TerminalUI.printError("Invalid note ID: \(noteId)")
                throw ExitCode.failure
            }

            if !force {
                print("Are you sure you want to delete note \(noteId)? [y/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                try await client.deleteNote(uuid)
                print("Deleted note: \(noteId)")
            } catch {
                TerminalUI.printError("Failed to delete note: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
