import MonadCore
import SwiftUI

public struct MessageListView: View {
    @Bindable var viewModel: ChatViewModel
    public var llmService: any LLMServiceProtocol
    public let onConfigureSettings: () -> Void

    @State private var isAtBottom = true

    public init(
        viewModel: ChatViewModel,
        llmService: any LLMServiceProtocol,
        onConfigureSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.llmService = llmService
        self.onConfigureSettings = onConfigureSettings
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
                            MessageBubble(
                                streamingThinking: viewModel.streamingThinking,
                                streamingContent: viewModel.streamingContent
                            )
                            .id("streaming")
                        }
                    }

                    if viewModel.isLoading && !viewModel.isStreaming {
                        loadingIndicator(text: "Connecting...")
                    }
                    
                    if viewModel.isExecutingTools {
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
            .onChange(of: viewModel.messages.count) {
                if isAtBottom {
                    withAnimation {
                        proxy.scrollTo("bottom-marker", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isStreaming) { oldValue, newValue in
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
            .onChange(of: viewModel.streamingContent) {
                if viewModel.isStreaming && isAtBottom {
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

            if !llmService.isConfigured {
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
