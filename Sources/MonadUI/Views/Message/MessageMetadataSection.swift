import MonadCore
import SwiftUI

public struct MessageMetadataSection: View {
    let message: Message?
    let isStreaming: Bool
    let role: Message.MessageRole
    @Binding var showingDebugInfo: Bool

    public init(
        message: Message?,
        isStreaming: Bool,
        role: Message.MessageRole,
        showingDebugInfo: Binding<Bool>
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.role = role
        self._showingDebugInfo = showingDebugInfo
    }

    public var body: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
            // Tags and Gathering Progress
            HStack(spacing: 4) {
                if role == .user, let progress = message?.gatheringProgress,
                    progress != .complete
                {
                    Button {
                        showingDebugInfo = true
                    } label: {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)

                            Text(progress.rawValue)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .textCase(.uppercase)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                if let tags = message?.tags, !tags.isEmpty {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            showingDebugInfo = true
                        } label: {
                            Text("#\(tag)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Performance Stats
            if let stats = message?.stats,
                stats.tokensPerSecond != nil || stats.totalTokens != nil
            {
                HStack(spacing: 8) {
                    if let tps = stats.tokensPerSecond {
                        Text(String(format: "%.1f tokens/sec", tps))
                    }
                    if let total = stats.totalTokens {
                        Text("\(total) tokens")
                    }

                    if role == .assistant && message?.debugInfo != nil {
                        Button {
                            showingDebugInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            }

            // Timestamp or Streaming status
            if let timestamp = message?.timestamp {
                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            } else if isStreaming {
                Text("Streaming...")
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.6))
                    .padding(.horizontal, 4)
            }
        }
    }
}
