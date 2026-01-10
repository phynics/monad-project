import MonadCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

public struct MessageToolCallsSection: View {
    let toolCalls: [ToolCall]
    @Binding var isExpanded: Bool

    public init(toolCalls: [ToolCall], isExpanded: Binding<Bool>) {
        self.toolCalls = toolCalls
        self._isExpanded = isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 9))
                    Text("Tool Calls (\(toolCalls.count))")
                        .font(.system(size: 10, weight: .bold))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolCalls) { toolCall in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.caption)
                                Text("Tool Used: \(toolCall.name)")
                                    .font(.caption)
                                    .bold()
                            }

                            if !toolCall.arguments.isEmpty {
                                ForEach(
                                    toolCall.arguments.sorted(by: { $0.key < $1.key }), id: \.key
                                ) { key, value in
                                    Text("\(key): \(String(describing: value))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .monospaced()
                                }
                                .padding(.leading, 20)
                            }

                            // Show in Finder for filesystem paths
                            if toolCall.name == "ls" || toolCall.name == "find",
                                let path = toolCall.arguments["path"]?.value as? String
                            {
                                Button(action: {
                                    #if os(macOS)
                                        let url = URL(fileURLWithPath: path)
                                        NSWorkspace.shared.selectFile(
                                            url.path, inFileViewerRootedAtPath: "")
                                    #endif
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder.fill")
                                        Text("Show in Finder")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 20)
                                .padding(.top, 4)
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(8)
            }
        }
    }
}
