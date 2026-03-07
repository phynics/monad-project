import Foundation
import MonadClient
import MonadShared

// MARK: - /agent command

struct AgentSlashCommand: SlashCommand {
    let name = "agent"
    let aliases: [String] = []
    let description = "Manage agent instances (list, attach, detach, create, info)"
    let category: String? = "Agent"

    var usage: String {
        "/agent [list|attach <agentId>|detach|create <name> <description>|info]"
    }

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.dropFirst().first ?? "info"

        switch subcommand {
        case "list":
            try await listAgents(context: context)
        case "attach":
            let idStr = args.dropFirst(2).first
            try await attachAgent(idStr: idStr, context: context)
        case "detach":
            try await detachAgent(context: context)
        case "create":
            let remaining = Array(args.dropFirst(2))
            try await createAgent(args: remaining, context: context)
        case "info":
            await showAgentInfo(context: context)
        default:
            await showAgentInfo(context: context)
        }
    }

    // MARK: - Subcommands

    private func listAgents(context: ChatContext) async throws {
        let agents = try await context.client.chat.listAgentInstances()
        if agents.isEmpty {
            TerminalUI.printInfo("No agent instances found. Create one with /agent create <name> <description>")
            return
        }

        print("")
        print(TerminalUI.bold("Agent Instances:"))
        for agent in agents {
            let isAttached = await context.repl.getCurrentAgent()?.id == agent.id
            let marker = isAttached ? TerminalUI.green("● ") : "  "
            let desc = agent.description.isEmpty ? "" : TerminalUI.dim(" — \(agent.description)")
            print("\(marker)\(TerminalUI.cyan(agent.name))\(desc) (\(agent.id.uuidString.prefix(8)))")
        }
        print("")
    }

    private func attachAgent(idStr: String?, context: ChatContext) async throws {
        guard let idStr else {
            TerminalUI.printError("Usage: /agent attach <agentId>")
            try await listAgents(context: context)
            return
        }

        // Allow prefix matching
        let agents = try await context.client.chat.listAgentInstances()
        let match: AgentInstance?
        if let uuid = UUID(uuidString: idStr) {
            match = agents.first { $0.id == uuid }
        } else {
            match = agents.first { $0.id.uuidString.lowercased().hasPrefix(idStr.lowercased()) }
        }

        guard let agent = match else {
            TerminalUI.printError("Agent not found: \(idStr)")
            return
        }

        try await context.client.chat.attachAgent(agentId: agent.id, to: context.timeline.id)
        await context.repl.setAgent(agent)
        TerminalUI.printSuccess("Attached agent '\(agent.name)' to timeline.")
    }

    private func detachAgent(context: ChatContext) async throws {
        guard let agent = await context.repl.getCurrentAgent() else {
            TerminalUI.printInfo("No agent currently attached.")
            return
        }
        try await context.client.chat.detachAgent(agentId: agent.id, from: context.timeline.id)
        await context.repl.setAgent(nil)
        TerminalUI.printSuccess("Detached agent '\(agent.name)' from timeline.")
    }

    private func createAgent(args: [String], context: ChatContext) async throws {
        guard args.count >= 2 else {
            TerminalUI.printError("Usage: /agent create <name> <description>")
            return
        }
        let agentName = args[0]
        let agentDescription = args[1...].joined(separator: " ")
        let agent = try await context.client.chat.createAgentInstance(name: agentName, description: agentDescription)
        TerminalUI.printSuccess("Created agent '\(agent.name)' (\(agent.id.uuidString.prefix(8)))")

        print("Attach to current timeline? [y/N] ", terminator: "")
        if let answer = readLine()?.lowercased().trimmingCharacters(in: .whitespaces), answer == "y" {
            try await context.client.chat.attachAgent(agentId: agent.id, to: context.timeline.id)
            await context.repl.setAgent(agent)
            TerminalUI.printSuccess("Attached '\(agent.name)' to current timeline.")
        }
    }

    private func showAgentInfo(context: ChatContext) async {
        if let agent = await context.repl.getCurrentAgent() {
            print("")
            print(TerminalUI.bold("Current Agent: ") + TerminalUI.cyan(agent.name))
            print(TerminalUI.dim("  ID:          \(agent.id.uuidString)"))
            if !agent.description.isEmpty {
                print(TerminalUI.dim("  Description: \(agent.description)"))
            }
            print(TerminalUI.dim("  Last active: \(TerminalUI.formatDate(agent.lastActiveAt))"))
            print("")
        } else {
            TerminalUI.printWarning("No agent attached to this timeline.")
            TerminalUI.printInfo("Use /agent list to see available agents, /agent attach <id> to attach one.")
        }
    }
}
