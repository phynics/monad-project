import MonadCore
import SwiftUI

public struct MessageToolResultView: View {
    let content: String
    @Binding var isExpanded: Bool
    let contentBody: AnyView

    public init(content: String, isExpanded: Binding<Bool>, contentBody: AnyView) {
        self.content = content
        self._isExpanded = isExpanded
        self.contentBody = contentBody
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation { isExpanded.toggle() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                    Text("Tool Result (\(content.count) chars)")
                        .font(.system(size: 10, weight: .bold))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded || content.count <= 300 {
                if isExpanded {
                    Divider().padding(.horizontal, 8).opacity(0.1)
                }
                contentBody
            } else {
                Text(content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .opacity(0.7)
            }
        }
    }
}
