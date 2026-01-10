import SwiftUI

public struct MessageThinkingSection: View {
    let thinking: String
    let isStreaming: Bool
    let isFinished: Bool
    @Binding var isExpanded: Bool
    let hasContent: Bool

    public init(
        thinking: String,
        isStreaming: Bool,
        isFinished: Bool,
        isExpanded: Binding<Bool>,
        hasContent: Bool
    ) {
        self.thinking = thinking
        self.isStreaming = isStreaming
        self.isFinished = isFinished
        self._isExpanded = isExpanded
        self.hasContent = hasContent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 3) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))

                    if isStreaming && !isFinished {
                        ProgressView()
                            .scaleEffect(0.3)
                            .frame(width: 8, height: 8)
                    }

                    Image(systemName: "brain")
                        .font(.system(size: 9))

                    Text(isStreaming && !isFinished ? "Thinking..." : "Thinking")
                        .font(.system(size: 10))

                    Spacer()
                }
                .foregroundColor(.secondary)
                .opacity(0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if isExpanded {
                Text(thinking)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .opacity(0.8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
        }

        if hasContent {
            Divider()
                .padding(.horizontal, 8)
                .opacity(0.2)
        }
    }
}
