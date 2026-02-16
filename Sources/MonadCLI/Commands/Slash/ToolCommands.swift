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

