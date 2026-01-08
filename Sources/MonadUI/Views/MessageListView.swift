import MonadCore
import SwiftUI

public struct MessageListView: View {
    public let messages: [Message]
    public let isStreaming: Bool
    public let isExecutingTools: Bool
    public let streamingThinking: String
    public let streamingContent: String
    public let isLoading: Bool
    public let llmServiceConfigured: Bool
    public let onConfigureSettings: () -> Void

    @State private var isAtBottom = true

    public init(
        messages: [Message],
        isStreaming: Bool,
        isExecutingTools: Bool = false,
        streamingThinking: String,
        streamingContent: String,
        isLoading: Bool,
        llmServiceConfigured: Bool,
        onConfigureSettings: @escaping () -> Void
    ) {
        self.messages = messages
        self.isStreaming = isStreaming
        self.isExecutingTools = isExecutingTools
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
                        loadingIndicator(text: "Connecting...")
                    }
                    
                    if isExecutingTools {
                        loadingIndicator(text: "Executing tools...")
                    }

                    // Bottom margin to prevent content being hidden by the floating button
                    Spacer(minLength: 80)
                        .id("bottom-margin")

                    Color.clear
                        .frame(height: 2)
                        .id("bottom-marker")
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    Button(action: {
                        withAnimation {
                            proxy.scrollTo("bottom-marker", anchor: .bottom)
                        }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.blue)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .padding(16)
                }
            }
            .onChange(of: messages.count) {
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
            .onChange(of: streamingContent) {
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

    private func loadingIndicator(text: String) -> some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 12)
    }
}
