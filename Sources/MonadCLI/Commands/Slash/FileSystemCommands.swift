import MonadShared
import Foundation
import MonadClient

// MARK: - Helpers

struct ResolvedPath {
    let workspaceId: UUID
    let path: String
    let workspaceName: String
}

private func resolvePath(_ input: String?, context: ChatContext) async throws -> ResolvedPath {
    let sessionWS = try await context.client.listSessionWorkspaces(sessionId: context.session.id)

    let targetWorkspaceId: UUID
    let wsName: String

    // Use REPL state for selection if available
    let selectedId = await context.repl.getSelectedWorkspace()

    if let selected = selectedId {
        targetWorkspaceId = selected
        wsName = "Selected"
    } else if let primary = sessionWS.primary {
        targetWorkspaceId = primary.id
        wsName = "Primary"
    } else {
        throw MonadClientError.unknown("No workspace selected or attached.")
    }

    guard let input = input, !input.isEmpty else {
        return ResolvedPath(workspaceId: targetWorkspaceId, path: "", workspaceName: wsName)
    }

    // Check for workspace prefix: @ws_id/path
    if input.hasPrefix("@") {
        let components = input.dropFirst().split(
            separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let wsRef = String(components[0])
        let path = components.count > 1 ? String(components[1]) : ""

        let allWorkspaces = try await context.client.listWorkspaces()
        if let ws = allWorkspaces.first(where: {
            $0.id.uuidString.lowercased().hasPrefix(wsRef.lowercased())
        }) {
            return ResolvedPath(workspaceId: ws.id, path: path, workspaceName: ws.uri.description)
        }
        throw MonadClientError.unknown("Workspace '@\(wsRef)' not found.")
    }

    // Default path logic
    if targetWorkspaceId == sessionWS.primary?.id && !input.contains("/") && !input.hasPrefix("Notes/")
        && !input.hasPrefix("Personas/")
    {
        return ResolvedPath(
            workspaceId: targetWorkspaceId, path: "Notes/\(input)", workspaceName: wsName)
    }

    return ResolvedPath(workspaceId: targetWorkspaceId, path: input, workspaceName: wsName)
}

// MARK: - Commands

struct LsCommand: SlashCommand {
    let name = "ls"
    let description = "List files in workspace"
    let category: String? = "File System"

    func run(args: [String], context: ChatContext) async throws {
        do {
            let resolved = try await resolvePath(args.first, context: context)
            let files = try await context.client.listFiles(workspaceId: resolved.workspaceId)

            let prefix =
                resolved.path.hasSuffix("/") || resolved.path.isEmpty
                ? resolved.path : "\(resolved.path)/"
            let filtered = files.filter { $0.hasPrefix(prefix) }

            if filtered.isEmpty {
                TerminalUI.printInfo("No files found in \(resolved.workspaceName):\(resolved.path)")
                return
            }

            print("\n\(TerminalUI.bold("\(resolved.workspaceName):\(resolved.path)"))\n")
            for file in filtered.prefix(50) {  // Cap at 50 explicitly
                let name = file.replacingOccurrences(of: prefix, with: "")
                if !name.isEmpty {
                    print("  📄 \(name)")
                }
            }
            if filtered.count > 50 {
                print("  ... and \(filtered.count - 50) more")
            }
            print("")
        } catch {
            TerminalUI.printError("ls failed: \(error.localizedDescription)")
        }
    }
}

struct CatCommand: SlashCommand {
    let name = "cat"
    let description = "Show file content"
    let category: String? = "File System"

    func run(args: [String], context: ChatContext) async throws {
        guard let pathInput = args.first else {
            TerminalUI.printError("Usage: /cat <path>")
            return
        }
        do {
            let resolved = try await resolvePath(pathInput, context: context)
            let content = try await context.client.getFileContent(
                workspaceId: resolved.workspaceId, path: resolved.path)
            print("\n" + TerminalUI.renderMarkdown(content) + "\n")
        } catch {
            TerminalUI.printError("cat failed: \(error.localizedDescription)")
        }
    }
}

struct RmCommand: SlashCommand {
    let name = "rm"
    let description = "Delete a file"
    let category: String? = "File System"

    func run(args: [String], context: ChatContext) async throws {
        guard let pathInput = args.first else {
            TerminalUI.printError("Usage: /rm <path>")
            return
        }
        do {
            let resolved = try await resolvePath(pathInput, context: context)
            print(
                "Are you sure you want to delete \(resolved.workspaceName):\(resolved.path)? (y/n): ",
                terminator: "")
            if readLine()?.lowercased() == "y" {
                try await context.client.deleteFile(
                    workspaceId: resolved.workspaceId, path: resolved.path)
                TerminalUI.printSuccess("Deleted \(resolved.path)")
            }
        } catch {
            TerminalUI.printError("rm failed: \(error.localizedDescription)")
        }
    }
}

struct WriteCommand: SlashCommand {
    let name = "write"
    let description = "Write content to a file"
    let category: String? = "File System"

    func run(args: [String], context: ChatContext) async throws {
        guard let pathInput = args.first else {
            TerminalUI.printError("Usage: /write <path>")
            return
        }
        do {
            let resolved = try await resolvePath(pathInput, context: context)
            print("Enter content (end with empty line):")
            var content = ""
            while let line = readLine() {
                if line.isEmpty { break }
                content += line + "\n"
            }
            try await context.client.writeFileContent(
                workspaceId: resolved.workspaceId, path: resolved.path, content: content)
            TerminalUI.printSuccess("Wrote \(resolved.path)")
        } catch {
            TerminalUI.printError("write failed: \(error.localizedDescription)")
        }
    }
}

struct EditCommand: SlashCommand {
    let name = "edit"
    let description = "Edit file in $EDITOR"
    let category: String? = "File System"

    func run(args: [String], context: ChatContext) async throws {
        guard let pathInput = args.first else {
            TerminalUI.printError("Usage: /edit <path>")
            return
        }
        do {
            let resolved = try await resolvePath(pathInput, context: context)
            let content = try await context.client.getFileContent(
                workspaceId: resolved.workspaceId, path: resolved.path)

            let filename = URL(fileURLWithPath: resolved.path).lastPathComponent
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try content.write(to: tempFile, atomically: true, encoding: .utf8)

            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, tempFile.path]

            try process.run()
            process.waitUntilExit()

            let updatedContent = try String(contentsOf: tempFile, encoding: .utf8)
            if updatedContent != content {
                try await context.client.writeFileContent(
                    workspaceId: resolved.workspaceId, path: resolved.path, content: updatedContent)
                TerminalUI.printSuccess("Updated \(resolved.path)")
            } else {
                TerminalUI.printInfo("No changes made.")
            }
            try? FileManager.default.removeItem(at: tempFile)
        } catch {
            TerminalUI.printError("edit failed: \(error.localizedDescription)")
        }
    }
}
