import MonadCore
import SwiftUI

public struct ChatHeaderView: View {
    public var llmService: LLMService
    @Binding public var showSidebar: Bool
    public let messagesEmpty: Bool
    public let onArchive: () -> Void
    public let onNotes: () -> Void
    public let onMemories: () -> Void
    public let onClear: () -> Void
    public let onArchiveCurrent: () -> Void
    public let onSettings: () -> Void
    public let onTools: () -> Void

    public init(
        llmService: LLMService,
        showSidebar: Binding<Bool>,
        messagesEmpty: Bool,
        onArchive: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onMemories: @escaping () -> Void = {},
        onClear: @escaping () -> Void,
        onArchiveCurrent: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onTools: @escaping () -> Void
    ) {
        self.llmService = llmService
        self._showSidebar = showSidebar
        self.messagesEmpty = messagesEmpty
        self.onArchive = onArchive
        self.onNotes = onNotes
        self.onMemories = onMemories
        self.onClear = onClear
        self.onArchiveCurrent = onArchiveCurrent
        self.onSettings = onSettings
        self.onTools = onTools
    }

    public var body: some View {
        HStack {
            Button {
                withAnimation {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")
            
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
                    
                    Menu {
                        Text("Current: \(llmService.configuration.modelName)")
                        Divider()
                        
                        if llmService.configuration.provider == .ollama {
                            Button("llama3") {
                                updateModel("llama3")
                            }
                            Button("mistral") {
                                updateModel("mistral")
                            }
                            Button("gemma") {
                                updateModel("gemma")
                            }
                            Button("deepseek-r1") {
                                updateModel("deepseek-r1")
                            }
                        } else {
                            // OpenAI / Compatible
                            Button("gpt-4o") {
                                updateModel("gpt-4o")
                            }
                            Button("gpt-4o-mini") {
                                updateModel("gpt-4o-mini")
                            }
                            Button("o1-preview") {
                                updateModel("o1-preview")
                            }
                            Button("claude-3.5-sonnet") {
                                updateModel("claude-3.5-sonnet")
                            }
                        }
                        
                        Divider()
                        Button("Settings...") {
                            onSettings()
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("Connected: \(llmService.configuration.modelName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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
            
            Button(action: onMemories) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Manage memories")

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
                
                Button(action: onMemories) {
                    Label("Memories", systemImage: "brain.head.profile")
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

    private func updateModel(_ name: String) {
        Task {
            var config = llmService.configuration
            config.modelName = name
            try? await llmService.updateConfiguration(config)
        }
    }
}
