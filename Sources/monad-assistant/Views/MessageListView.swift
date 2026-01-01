import SwiftUI

struct MessageListView: View {
    let messages: [Message]
    let isStreaming: Bool
    let streamingThinking: String
    let streamingContent: String
    let isLoading: Bool
    let llmServiceConfigured: Bool
    let onConfigureSettings: () -> Void

    var body: some View {
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
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingContent) { _ in
                if isStreaming {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
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
