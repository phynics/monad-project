import MonadCore
import SwiftUI

public struct MessageSummaryBubble: View {
    let message: Message
    @Binding var isExpanded: Bool

    public init(message: Message, isExpanded: Binding<Bool>) {
        self.message = message
        self._isExpanded = isExpanded
    }

    public var body: some View {
        if message.summaryType == .broad {
            broadSummary
        } else {
            topicSummary
        }
    }

    private var broadSummary: some View {
        Button(action: { withAnimation { isExpanded.toggle() } }) {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text(isExpanded ? message.content : "Broad Summary")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if !isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private var topicSummary: some View {
        Button(action: { withAnimation { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 4)
                    .cornerRadius(2)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Topic Summary")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.secondary)

                    if isExpanded {
                        Text(message.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(message.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
