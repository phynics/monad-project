import MonadCore
import SwiftUI

/// Simple UI to enable/disable tools for current session
struct ToolsSettingsView: View {
    var toolManager: SessionToolManager
    let availableTools: [Tool]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableTools, id: \.id) { tool in
                    ToolRow(
                        tool: tool,
                        isEnabled: toolManager.enabledTools.contains(tool.id),
                        onToggle: {
                            toolManager.toggleTool(tool.id)
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
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ToolRow: View {
    let tool: Tool
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
