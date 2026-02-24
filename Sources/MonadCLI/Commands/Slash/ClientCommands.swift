import Foundation
import MonadClient

struct ClientCommand: SlashCommand {
    let name = "client"
    let aliases = ["clients"]
    let description = "Manage registered clients"
    let category: String? = "Tools & Environment"
    let usage = "/client [list|remove] <args>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            try await listClients(context: context)
        case "remove", "rm", "delete":
            if args.count > 1 {
                try await removeClient(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /client remove <id>")
            }
        default:
            try await listClients(context: context)
        }
    }

    private func listClients(context: ChatContext) async throws {
        let clients = try await context.client.listClients()
        print("\n\(TerminalUI.bold("Registered Clients:"))\n")

        if clients.isEmpty {
            print("  No clients found.\n")
            return
        }

        for client in clients {
            print("  \(TerminalUI.bold(client.displayName)) (\(client.hostname))")
            print("    ID: \(TerminalUI.dim(client.id.uuidString))")
            print("    Platform: \(client.platform)")
            if let lastSeen = client.lastSeenAt {
                print("    Last Seen: \(lastSeen.formatted())")
            }
            print("")
        }
    }

    private func removeClient(_ idStr: String, context: ChatContext) async throws {
        guard let uuid = UUID(uuidString: idStr) else {
            TerminalUI.printError("Invalid UUID")
            return
        }

        do {
            try await context.client.deleteClient(uuid)
            TerminalUI.printSuccess("Removed client \(uuid.uuidString)")
        } catch {
            TerminalUI.printError("Failed to remove client: \(error.localizedDescription)")
        }
    }
}
