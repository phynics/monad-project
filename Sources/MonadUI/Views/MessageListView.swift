import MonadCore
import SwiftUI

public struct MessageListView: View {
    public let messages: [Message]
    public let isStreaming: Bool
    public let streamingThinking: String
    public let streamingContent: String
    public let isLoading: Bool
    public let llmServiceConfigured: Bool
    public let onConfigureSettings: () -> Void

    @State private var isAtBottom = true

    public init(
        messages: [Message],
        isStreaming: Bool,
        streamingThinking: String,
        streamingContent: String,
        isLoading: Bool,
        llmServiceConfigured: Bool,
        onConfigureSettings: @escaping () -> Void
    ) {
        self.messages = messages
        self.isStreaming = isStreaming
        self.streamingThinking = streamingThinking
        self.streamingContent = streamingContent
        self.isLoading = isLoading
        self.llmServiceConfigured = llmServiceConfigured
        self.onConfigureSettings = onConfigureSettings
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isStreaming {
                            MessageBubble(
                                streamingThinking: streamingThinking,
                                streamingContent: streamingContent
                            )
                            .id("streaming")
                        }
                    }

                    if isLoading && !isStreaming {
                        loadingIndicator
                    }

                    Color.clear
                        .frame(height: 50)
                        .id("bottom-marker")
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                if isAtBottom {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(16)
                        .transition(.opacity)
                }
            }
            .onChange(of: messages.count) { _ in
                if isAtBottom {
                    withAnimation {
                        proxy.scrollTo("bottom-marker", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isStreaming) { oldValue, newValue in
                if oldValue && !newValue {
                    // Streaming finished, ensure we are at the bottom if we were following
                    if isAtBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation {
                                proxy.scrollTo("bottom-marker", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .onChange(of: streamingContent) { _ in
                if isStreaming && isAtBottom {
                    proxy.scrollTo("bottom-marker", anchor: .bottom)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Start a conversation")
                .font(.headline)
                .foregroundColor(.secondary)

            if !llmServiceConfigured {
                Button("Configure Settings") {
                    onConfigureSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 12)
    }
}
