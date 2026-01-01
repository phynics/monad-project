import MonadMCP
import Shared
import SwiftUI

@main
struct MonadAssistantApp: App {
    @State private var llmService = LLMService()
    @State private var persistenceManager: PersistenceManager
    @State private var mcpTransport: StdioTransport
    @State private var mcpClient: MCPClient

    init() {
        let persistence = try! PersistenceService.create()
        let manager = PersistenceManager(persistence: persistence)
        self._persistenceManager = State(initialValue: manager)

        // Setup MCP (macOS only)
        let transport = StdioTransport(
            command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"])
        let client = MCPClient(transport: transport)
        self._mcpTransport = State(initialValue: transport)
        self._mcpClient = State(initialValue: client)

        // Register MCP as a tool provider
        llmService.registerToolProvider(client)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                llmService: llmService,
                persistenceManager: persistenceManager
            )
        }

        // Separate Settings Window - works better on macOS for text field focus
        Window("Settings", id: "settings") {
            SettingsView(llmService: llmService, persistenceManager: persistenceManager) {
                Section {
                    NavigationLink {
                        MCPSettingsView(servers: $llmService.configuration.mcpServers)
                    } label: {
                        HStack {
                            Label("Manage MCP Servers", systemImage: "server.rack")
                            Spacer()
                            Text("\(llmService.configuration.mcpServers.count) servers")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Model Context Protocol")
                }
            }
            .frame(minWidth: 600, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 600)
    }
}
