import ArgumentParser
import Foundation
import MonadClient
import MonadCore

struct WorkspaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workspace",
        abstract: "Manage workspaces and attachments",
        subcommands: [List.self, Attach.self, Detach.self, Register.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List workspaces")

        @OptionGroup var clientOptions: ClientOptions

        func run() async throws {
            let client = MonadClient(configuration: clientOptions.toConfiguration())

            // Ensure registered
            _ = try await RegistrationManager.shared.ensureRegistered(client: client)

            do {
                let workspaces = try await client.listWorkspaces()
                print("\n\(TerminalUI.bold("Workspaces"))")
                if workspaces.isEmpty {
                    print("No workspaces found.")
                } else {
                    for ws in workspaces {
                        print("- \(TerminalUI.bold(ws.uri.description)) (ID: \(ws.id))")
                        print("  Host: \(ws.hostType), Trust: \(ws.trustLevel)")
                        if let path = ws.rootPath {
                            print("  Root: \(path)")
                        }
                        if !ws.tools.isEmpty {
                            print("  Tools: \(ws.tools.count) registered")
                        }
                        print("")
                    }
                }
            } catch {
                TerminalUI.printError("Failed to list workspaces: \(error.localizedDescription)")
            }
        }
    }

    struct Register: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Register a new workspace")

        @OptionGroup var clientOptions: ClientOptions

        @Argument(help: "Workspace URI (e.g. macbook:~/dev/project)")
        var uri: String

        @Option(help: "Host type (client/server)")
        var type: String = "client"

        @Option(help: "Root path")
        var path: String?

        func run() async throws {
            let client = MonadClient(configuration: clientOptions.toConfiguration())

            guard let hostType = WorkspaceHostType(rawValue: type) else {
                TerminalUI.printError("Invalid host type. Use 'client' or 'server'.")
                return
            }

            guard let wsURI = WorkspaceURI(parsing: uri) else {
                TerminalUI.printError("Invalid URI format. Expected host:path")
                return
            }

            do {
                // Determine owner ID from client identity?
                // For CLI, we might default to no owner or current client?
                // Client registration happens on startup.
                // We'll leave ownerId nil for now or fetch client info first.
                // Let's assume nil for manual registration or server assigns.

                let ws = try await client.createWorkspace(
                    uri: wsURI,
                    hostType: hostType,
                    ownerId: nil,
                    rootPath: path,
                    trustLevel: .full
                )
                TerminalUI.printSuccess("Registered workspace: \(ws.uri) (ID: \(ws.id))")
            } catch {
                TerminalUI.printError("Failed to register workspace: \(error.localizedDescription)")
            }
        }
    }

    struct Attach: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Attach workspace to session")

        @OptionGroup var clientOptions: ClientOptions

        @Argument(help: "Workspace ID or URI")
        var workspace: String

        @Option(name: .shortAndLong, help: "Session ID")
        var session: String

        @Flag(help: "Set as primary workspace")
        var primary: Bool = false

        func run() async throws {
            let client = MonadClient(configuration: clientOptions.toConfiguration())

            guard let sessionId = UUID(uuidString: session) else {
                TerminalUI.printError("Invalid session ID")
                return
            }

            // Resolve workspace ID
            var workspaceId: UUID?
            if let id = UUID(uuidString: workspace) {
                workspaceId = id
            } else {
                // Try to find by URI
                if let workspaces = try? await client.listWorkspaces() {
                    workspaceId = workspaces.first(where: { $0.uri.description == workspace })?.id
                }
            }

            guard let wId = workspaceId else {
                TerminalUI.printError("Workspace not found")
                return
            }

            do {
                try await client.attachWorkspace(wId, to: sessionId, isPrimary: primary)
                TerminalUI.printSuccess("Attached workspace to session")
            } catch {
                TerminalUI.printError("Failed to attach: \(error.localizedDescription)")
            }
        }
    }

    struct Detach: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Detach workspace from session")

        @OptionGroup var clientOptions: ClientOptions

        @Argument(help: "Workspace ID")
        var workspaceId: String

        @Option(name: .shortAndLong, help: "Session ID")
        var session: String

        func run() async throws {
            let client = MonadClient(configuration: clientOptions.toConfiguration())

            guard let sessionId = UUID(uuidString: session) else {
                TerminalUI.printError("Invalid session ID")
                return
            }

            guard let wId = UUID(uuidString: workspaceId) else {
                TerminalUI.printError("Invalid workspace ID")
                return
            }

            do {
                try await client.detachWorkspace(wId, from: sessionId)
                TerminalUI.printSuccess("Detached workspace from session")
            } catch {
                TerminalUI.printError("Failed to detach: \(error.localizedDescription)")
            }
        }
    }
}
