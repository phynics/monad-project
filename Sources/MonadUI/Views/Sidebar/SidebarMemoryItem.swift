import MonadCore
import SwiftUI

public struct SidebarMemoryItem: View {
    let am: ActiveMemory
    let onTogglePin: () -> Void
    let onRemove: () -> Void

    public init(am: ActiveMemory, onTogglePin: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.am = am
        self.onTogglePin = onTogglePin
        self.onRemove = onRemove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(am.memory.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Button(action: onTogglePin) {
                        Image(systemName: am.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(am.isPinned ? .blue : .secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(am.memory.content)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(am.isPinned ? Color.blue.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(am.isPinned ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}
