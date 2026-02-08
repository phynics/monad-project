import Foundation
import MonadClient
import MonadCore

struct WorkspaceSlashCommand: SlashCommand {
    let name = "workspace"
    let aliases = ["workspaces"]
    let description = "Manage workspaces"
    let category: String? = "Tools & Environment"
    let usage = "/workspace [list|select|attach|detach] <args>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            try await listWorkspaces(context: context)
        case "select", "use":
            if args.count > 1 {
                try await selectWorkspace(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /workspace select <id>")
            }
        case "attach":
            if args.count > 1 {
                if let uuid = UUID(uuidString: args[1]) {
                    try await context.client.attachWorkspace(
                        uuid, to: context.session.id, isPrimary: false)
                    TerminalUI.printSuccess("Attached workspace \(uuid.uuidString).")
                } else {
                    // Try to match by URI/Name logic if needed, but UUID is safest for now
                    TerminalUI.printError("Invalid UUID. Use 'monad workspace list' to see IDs.")
                }
            } else {
                TerminalUI.printInfo("Interactively attaching workspace...")
                try await interactiveAttach(context: context)
            }
        case "detach":
            if args.count > 1 {
                if let uuid = UUID(uuidString: args[1]) {
                    try await context.client.detachWorkspace(uuid, from: context.session.id)
                    TerminalUI.printSuccess("Detached workspace \(uuid.uuidString).")
                } else {
                    TerminalUI.printError("Invalid UUID")
                }
            } else {
                TerminalUI.printError("Usage: /workspace detach <id>")
            }
        default:
            try await listWorkspaces(context: context)
        }
    }

    private func listWorkspaces(context: ChatContext) async throws {
        let allWorkspaces = try await context.client.listWorkspaces()
        let sessionWS = try await context.client.listSessionWorkspaces(
            sessionId: context.session.id)

        let primaryId = sessionWS.primary?.id
        let attachedIds = Set(sessionWS.attached.map { $0.id })
        
        let primaryWorkspace = allWorkspaces.first(where: { $0.id == primaryId })
        let attachedWorkspaces = allWorkspaces.filter { attachedIds.contains($0.id) && $0.id != primaryId }
        let availableWorkspaces = allWorkspaces.filter { $0.id != primaryId && !attachedIds.contains($0.id) }

        print("\n\(TerminalUI.bold("Current Session Workspaces:"))")
        
        if let primary = primaryWorkspace {
            printWorkspace(primary, marker: "★", color: "green")
        } else {
             print("  \(TerminalUI.dim("No primary workspace"))")
        }
        
        for ws in attachedWorkspaces {
            printWorkspace(ws, marker: "●", color: "blue")
        }

        if !availableWorkspaces.isEmpty {
            print("\n\(TerminalUI.bold("Available Workspaces:"))")
            for ws in availableWorkspaces {
                printWorkspace(ws, marker: "○", color: "white")
            }
        }
        
        print("")
        print("  ★ Primary  ● Attached  ○ Available")
        print("")
    }

    private func printWorkspace(_ ws: Workspace, marker: String, color: String) {
        let markerStr: String
        switch color {
        case "green": markerStr = TerminalUI.green(marker)
        case "blue": markerStr = TerminalUI.blue(marker)
        default: markerStr = marker
        }
        
        print("  \(markerStr) \(TerminalUI.bold(ws.uri.description))")
        print("     ID: \(TerminalUI.dim(ws.id.uuidString))")
        if let path = ws.rootPath {
            print("     Path: \(TerminalUI.dim(path))")
        }
        if !ws.tools.isEmpty {
            let toolNames = ws.tools.map { (ref: ToolReference) -> String in
                switch ref {
                case .known(let id): return id
                case .custom(let def): return def.name
                }
            }
            print("     Tools: \(toolNames.joined(separator: ", "))")
        }
    }

    private func selectWorkspace(_ idStr: String, context: ChatContext) async throws {
        // Simple select by ID prefix
        let workspaces = try await context.client.listWorkspaces()
        if let match = workspaces.first(where: { $0.id.uuidString.hasPrefix(idStr) }) {
            await context.repl.setSelectedWorkspace(match.id)
            TerminalUI.printSuccess("Selected workspace for context: \(match.uri.description)")
        } else {
            TerminalUI.printError("No workspace found with ID prefix: \(idStr)")
        }
    }

    private func interactiveAttach(context: ChatContext) async throws {
        let workspaces = try await context.client.listWorkspaces()
        guard !workspaces.isEmpty else {
            TerminalUI.printWarning("No workspaces available to attach.")
            return
        }

        print("\nAvailable Workspaces:")
        for (i, ws) in workspaces.enumerated() {
            print("  \(i+1). \(ws.uri.description) (\(ws.id.uuidString.prefix(8)))")
        }
        print("\nSelect workspace to attach (1-\(workspaces.count)): ", terminator: "")

        if let input = readLine(), let index = Int(input), index > 0 && index <= workspaces.count {
            let selected = workspaces[index - 1]
            try await context.client.attachWorkspace(
                selected.id, to: context.session.id, isPrimary: false)
            TerminalUI.printSuccess("Attached \(selected.uri.description)")
        } else {
            print("Aborted.")
        }
    }
}
