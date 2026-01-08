import MonadMCP
import MonadCore
import MonadUI
import SwiftUI

@main
struct MonadAssistantApp: App {
    @State private var llmService = LLMService()
    @State private var persistenceManager: PersistenceManager
    @State private var chatViewModel: ChatViewModel
    @State private var mcpTransport: StdioTransport
    @State private var mcpClient: MCPClient
    
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let persistence = try! PersistenceService.create()
        let manager = PersistenceManager(persistence: persistence)
        self._persistenceManager = State(initialValue: manager)
        
        let llm = LLMService()
        self._llmService = State(initialValue: llm)
        
        self._chatViewModel = State(initialValue: ChatViewModel(llmService: llm, persistenceManager: manager))

        // Setup MCP (macOS only)
        let transport = StdioTransport(
            command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"])
        let client = MCPClient(transport: transport)
        self._mcpTransport = State(initialValue: transport)
        self._mcpClient = State(initialValue: client)

        // Register MCP as a tool provider
        llm.registerToolProvider(client)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: chatViewModel,
                llmService: llmService,
                persistenceManager: persistenceManager
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                // Auto-archive when app is closing or moving to background
                chatViewModel.archiveConversation { }
            }
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
