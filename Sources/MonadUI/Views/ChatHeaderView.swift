import MonadCore
import SwiftUI

public struct ChatHeaderView: View {
    public var llmManager: LLMManager
    @Binding public var showSidebar: Bool
    public var performanceMetrics: PerformanceMetrics
    public let messagesEmpty: Bool
    public let onArchive: () -> Void
    public let onNotes: () -> Void
    public let onMemories: () -> Void
    public let onClear: () -> Void
    public let onArchiveCurrent: () -> Void
    public let onSettings: () -> Void
    public let onTools: () -> Void
    public let onCompress: (CompressionScope) -> Void
    public let onVacuum: () -> Void

    public init(
        llmManager: LLMManager,
        showSidebar: Binding<Bool>,
        performanceMetrics: PerformanceMetrics,
        messagesEmpty: Bool,
        onArchive: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onMemories: @escaping () -> Void = {},
        onClear: @escaping () -> Void,
        onArchiveCurrent: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onTools: @escaping () -> Void,
        onCompress: @escaping (CompressionScope) -> Void,
        onVacuum: @escaping () -> Void
    ) {
        self.llmManager = llmManager
        self._showSidebar = showSidebar
        self.performanceMetrics = performanceMetrics
        self.messagesEmpty = messagesEmpty
        self.onArchive = onArchive
        self.onNotes = onNotes
        self.onMemories = onMemories
        self.onClear = onClear
        self.onArchiveCurrent = onArchiveCurrent
        self.onSettings = onSettings
        self.onTools = onTools
        self.onCompress = onCompress
        self.onVacuum = onVacuum
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

            if let speed = performanceMetrics.lastSpeed {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.caption)
                    Text("\(String(format: "%.1f", speed)) t/s")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundColor(performanceMetrics.isSlow ? .red : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(performanceMetrics.isSlow ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }

            Spacer()

            // Status Indicator
            if llmManager.isConfigured {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Menu {
                        Text("Switch Provider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        ForEach(LLMProvider.allCases) { provider in
                            if let config = llmManager.configuration.providers[provider] {
                                Button {
                                    updateProvider(provider)
                                } label: {
                                    HStack {
                                        if provider == llmManager.configuration.provider {
                                            Label("\(provider.rawValue) (\(config.modelName))", systemImage: "checkmark")
                                        } else {
                                            Text("\(provider.rawValue) (\(config.modelName))")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        Button("Settings...") {
                            onSettings()
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(llmManager.configuration.provider.rawValue): \(llmManager.configuration.modelName)")
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
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Button("Configure...") {
                        onSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red)
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
                
                Divider()
                
                Menu("Developer") {
                    Button("Compress Context (Topic)") {
                        onCompress(.topic)
                    }
                    Button("Force Broad Summary") {
                        onCompress(.broad)
                    }
                    Button("Vacuum Memories") {
                        onVacuum()
                    }
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

    private func updateProvider(_ provider: LLMProvider) {
        Task {
            var config = llmManager.configuration
            config.activeProvider = provider
            try? await llmManager.updateConfiguration(config)
        }
    }
}
