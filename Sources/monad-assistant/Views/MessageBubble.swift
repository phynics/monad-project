import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: Message?
    let isStreaming: Bool
    let streamingThinking: String
    let streamingContent: String

    @State private var isThinkingExpanded = true
    @State private var showingDebugInfo = false

    init(message: Message) {
        self.message = message
        self.isStreaming = false
        self.streamingThinking = ""
        self.streamingContent = ""
    }

    init(streamingThinking: String, streamingContent: String) {
        self.message = nil
        self.isStreaming = true
        self.streamingThinking = streamingThinking
        self.streamingContent = streamingContent
    }

    var body: some View {
        HStack {
            if role == .user {
                Spacer()
            }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    // Thinking section
                    if hasThinking {
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: { withAnimation { isThinkingExpanded.toggle() } }) {
                                HStack(spacing: 3) {
                                    Image(
                                        systemName: isThinkingExpanded
                                            ? "chevron.down" : "chevron.right"
                                    )
                                    .font(.system(size: 8))
                                    if isStreaming && !isThinkingFinished {
                                        ProgressView()
                                            .scaleEffect(0.3)
                                            .frame(width: 8, height: 8)
                                    }
                                    Image(systemName: "brain")
                                        .font(.system(size: 9))
                                    Text(
                                        isStreaming && !isThinkingFinished
                                            ? "Thinking..." : "Thinking"
                                    )
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

                            if isThinkingExpanded {
                                Text(displayThinking)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .opacity(0.8)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                            }
                        }

                        if hasContent {
                            Divider()
                                .padding(.horizontal, 8)
                                .opacity(0.2)
                        }
                    }

                    // Main content
                    if hasContent {
                        HStack(alignment: .bottom, spacing: 0) {
                            Text(displayContent)
                                .padding(12)

                            if isStreaming {
                                Text("▋")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.blue)
                                    .padding(.bottom, 12)
                                    .padding(.trailing, 8)
                                    .opacity(0.7)
                                    .modifier(BlinkingModifier())
                            }
                        }
                    }

                    // Tool Calls
                    if let toolCalls = message?.toolCalls, !toolCalls.isEmpty {
                        if hasContent {
                            Divider().padding(.horizontal, 8).opacity(0.2)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(toolCalls) { toolCall in
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.caption)
                                    Text("Tool Used: \(toolCall.name)")
                                        .font(.caption)
                                        .bold()
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

                    if isStreaming && !hasThinking && !hasContent {
                        // Loading state
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Monad is thinking...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                    }
                }
                .background(backgroundColor)
                .foregroundColor(textColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isStreaming ? Color.blue.opacity(0.1) : Color.clear, lineWidth: 1)
                )

                if let timestamp = message?.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if isStreaming {
                    Text("Streaming...")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.6))
                        .padding(.leading, 4)
                }
            }

            if role == .assistant {
                Spacer()
            }
        }
        .contextMenu {
            if let message = message {
                if message.debugInfo != nil {
                    Button("Show Debug Info") {
                        showingDebugInfo = true
                    }
                }

                Button("Copy Content") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                }
            }
        }
        .sheet(isPresented: $showingDebugInfo) {
            if let message = message, let debugInfo = message.debugInfo {
                MessageDebugView(message: message, debugInfo: debugInfo)
            }
        }
    }

    // MARK: - Helpers

    private var role: Message.MessageRole {
        message?.role ?? .assistant
    }

    private var hasThinking: Bool {
        if isStreaming {
            return !streamingThinking.isEmpty
        }
        return message?.think != nil && !(message?.think?.isEmpty ?? true)
    }

    private var isThinkingFinished: Bool {
        !isStreaming || !streamingContent.isEmpty
    }

    private var displayThinking: String {
        isStreaming ? streamingThinking : (message?.think ?? "")
    }

    private var hasContent: Bool {
        if isStreaming {
            return !streamingContent.isEmpty
        }
        return !message!.content.isEmpty
    }

    private var displayContent: String {
        isStreaming ? streamingContent : (message?.content ?? "")
    }

    private var backgroundColor: Color {
        if isStreaming {
            return Color.gray.opacity(0.15)
        }
        switch role {
        case .user:
            return Color.blue
        case .assistant:
            return Color.gray.opacity(0.2)
        case .system:
            return Color.orange.opacity(0.2)
        case .tool:
            return Color.purple.opacity(0.1)
        }
    }

    private var textColor: Color {
        if isStreaming {
            return .primary
        }
        switch role {
        case .user:
            return .white
        case .assistant, .system:
            return .primary
        case .tool:
            return .primary
        }
    }
}

struct BlinkingModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true))
                {
                    isVisible.toggle()
                }
            }
    }
}
