import SwiftUI

struct ChatHeaderView: View {
    var llmService: LLMService
    let messagesEmpty: Bool
    let onArchive: () -> Void
    let onNotes: () -> Void
    let onClear: () -> Void
    let onArchiveCurrent: () -> Void
    let onSettings: () -> Void
    let onTools: () -> Void

    var body: some View {
        HStack {
            Text("Monad Assistant")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            // Status Indicator
            if llmService.isConfigured {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Archive button
            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("View archived conversations")

            Button(action: onNotes) {
                Image(systemName: "note.text")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Context notes")

            // Menu for more options
            Menu {
                Button(action: onArchiveCurrent) {
                    Label("Archive This Conversation", systemImage: "archivebox")
                }
                .disabled(messagesEmpty)

                Button(action: onClear) {
                    Label("Clear Conversation", systemImage: "trash")
                }
                .disabled(messagesEmpty)

                Divider()

                Button(action: onNotes) {
                    Label("Context Notes", systemImage: "note.text")
                }

                Button(action: onTools) {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }

                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }
}
