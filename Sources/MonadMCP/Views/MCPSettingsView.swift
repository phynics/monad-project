import Shared
import SwiftUI

public struct MCPSettingsView: View {
    @Binding public var servers: [MCPServerConfiguration]
    @State private var showingAddSheet = false
    @State private var editingServer: MCPServerConfiguration?

    public init(servers: Binding<[MCPServerConfiguration]>) {
        self._servers = servers
    }

    public var body: some View {
        VStack {
            List {
                ForEach(servers) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                                .font(.headline)
                            Text(server.command + " " + server.arguments.joined(separator: " "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if server.isEnabled {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }

                        Button("Edit") {
                            editingServer = server
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    servers.remove(atOffsets: indexSet)
                }
            }
            .listStyle(.inset)

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add MCP Server", systemImage: "plus")
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("MCP Servers")
        .sheet(isPresented: $showingAddSheet) {
            ServerEditView(
                server: MCPServerConfiguration(
                    name: "", command: "", arguments: [], environment: [:])
            ) { newServer in
                servers.append(newServer)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingServer) { server in
            ServerEditView(server: server) { updatedServer in
                if let index = servers.firstIndex(where: { $0.id == server.id }) {
                    servers[index] = updatedServer
                }
                editingServer = nil
            }
        }
    }
}

struct ServerEditView: View {
    @State var server: MCPServerConfiguration
    var onSave: (MCPServerConfiguration) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var argsString: String = ""
    @State private var envString: String = ""

    var body: some View {
        Form {
            Section("Server Details") {
                TextField("Name", text: $server.name)
                TextField("Command", text: $server.command)

                TextField("Arguments (space separated)", text: $argsString)

                Text("Environment Variables (KEY=VALUE per line)")
                    .font(.caption)
                TextEditor(text: $envString)
                    .frame(height: 100)
                    .font(.system(.caption, design: .monospaced))

                Toggle("Enabled", isOn: $server.isEnabled)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    // Parse args
                    server.arguments = argsString.split(separator: " ").map(String.init)

                    // Parse env
                    var env: [String: String] = [:]
                    envString.enumerateLines { line, _ in
                        let parts = line.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 {
                            env[String(parts[0])] = String(parts[1])
                        }
                    }
                    server.environment = env

                    onSave(server)
                }
                .disabled(server.name.isEmpty || server.command.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
        .onAppear {
            argsString = server.arguments.joined(separator: " ")
            envString = server.environment.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        }
    }
}
