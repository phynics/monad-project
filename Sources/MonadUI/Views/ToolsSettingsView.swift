import MonadCore
import SwiftUI

/// Simple UI to enable/disable tools for current session
struct ToolsSettingsView: View {
    var toolManager: SessionToolManager
    @State private var availableTools: [any MonadCore.Tool] = []
    @State private var enabledTools: Set<String> = []
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableTools, id: \.id) { tool in
                    ToolRow(
                        tool: tool,
                        isEnabled: enabledTools.contains(tool.id),
                        onToggle: {
                            Task {
                                await toolManager.toggleTool(tool.id)
                                await refreshState()
                            }
                        }
                    )
                }
            }
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await refreshState()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func refreshState() async {
        let tools = await toolManager.getAvailableTools()
        let enabled = await toolManager.enabledTools
        await MainActor.run {
            self.availableTools = tools
            self.enabledTools = enabled
        }
    }
}

struct ToolRow: View {
    let tool: any MonadCore.Tool
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tool.name)
                        .font(.headline)

                    if tool.requiresPermission {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("Requires permission")
                    }
                }

                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}