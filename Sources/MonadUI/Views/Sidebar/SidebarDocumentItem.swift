import MonadCore
import SwiftUI

public struct SidebarDocumentItem: View {
    let doc: DocumentContext
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onUnload: () -> Void

    public init(
        doc: DocumentContext,
        onSelect: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onUnload: @escaping () -> Void
    ) {
        self.doc = doc
        self.onSelect = onSelect
        self.onTogglePin = onTogglePin
        self.onUnload = onUnload
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: onSelect) {
                    Text(fileName(from: doc.path))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    Button(action: onTogglePin) {
                        Image(systemName: doc.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(doc.isPinned ? .blue : .secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)

                    Button(action: onUnload) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onSelect) {
                Text(doc.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(doc.isPinned ? Color.blue.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(doc.isPinned ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
