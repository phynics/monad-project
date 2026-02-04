import Foundation
import MonadClient

struct ToolCommand: SlashCommand {
    let name = "tool"
    let aliases = ["tools"]
    let description = "Manage tools"
    let category: String? = "Tools & Environment"
    let usage = "/tool [list|enable|disable] <name>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            try await listTools(context: context)
        case "enable":
            if args.count > 1 {
                try await context.client.enableTool(args[1], sessionId: context.session.id)
                TerminalUI.printSuccess("Enabled tool: \(args[1])")
            } else {
                TerminalUI.printError("Usage: /tool enable <name>")
            }
        case "disable":
            if args.count > 1 {
                try await context.client.disableTool(args[1], sessionId: context.session.id)
                TerminalUI.printSuccess("Disabled tool: \(args[1])")
            } else {
                TerminalUI.printError("Usage: /tool disable <name>")
            }
        default:
            try await listTools(context: context)
        }
    }

    private func listTools(context: ChatContext) async throws {
        let tools = try await context.client.listTools(sessionId: context.session.id)
        if tools.isEmpty {
            TerminalUI.printInfo("No tools available.")
            return
        }

        print("\n\(TerminalUI.bold("Available Tools:"))\n")
        for tool in tools {
            let status = tool.isEnabled ? TerminalUI.green("●") : TerminalUI.dim("○")
            let sourceStr = tool.source.map { " (\($0))" } ?? ""
            print("  \(status) \(TerminalUI.bold(tool.name))\(TerminalUI.dim(sourceStr))")
            print("    \(TerminalUI.dim(tool.description))")
        }
        print("")
    }
}

struct PersonaCommand: SlashCommand {
    let name = "persona"
    let aliases = ["personas"]
    let description = "Manage personas"
    let category: String? = "Tools & Environment"
    let usage = "/persona [list|use] <name>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            let personas = try await context.client.listPersonas()
            print("\n\(TerminalUI.bold("Available Personas:"))")
            for p in personas {
                print("  👤 \(p.id)")
            }
            print("")
        case "use", "set":
            if args.count > 1 {
                let name = args[1]
                let file = name.hasSuffix(".md") ? name : "\(name).md"
                try await context.client.updatePersona(file, sessionId: context.session.id)
                TerminalUI.printSuccess("Persona updated to \(file)")
            } else {
                TerminalUI.printError("Usage: /persona use <name>")
            }
        default:
            TerminalUI.printError("Unknown subcommand. Use list or use.")
        }
    }
}
