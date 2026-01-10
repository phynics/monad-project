import MonadCore
import RegexBuilder
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

public struct MessageBubble: View {
    public let message: Message?
    public let isStreaming: Bool
    public let streamingThinking: String
    public let streamingContent: String

    @State private var isThinkingExpanded = false
    @State private var isToolResultExpanded = false
    @State private var isToolCallsExpanded = false
    @State private var isSummaryExpanded = false
    @State private var showingDebugInfo = false
    @State private var showingSubagentInfo = false

    public init(message: Message) {
        self.message = message
        self.isStreaming = false
        self.streamingThinking = ""
        self.streamingContent = ""
        self._isToolCallsExpanded = State(initialValue: true)
    }

    public init(streamingThinking: String, streamingContent: String) {
        self.message = nil
        self.isStreaming = true
        self.streamingThinking = streamingThinking
        self.streamingContent = streamingContent
        self._isThinkingExpanded = State(initialValue: true)
        self._isToolCallsExpanded = State(initialValue: true)
    }

    public var body: some View {
        if let message = message, message.isSummary {
            MessageSummaryBubble(message: message, isExpanded: $isSummaryExpanded)
        } else {
            mainBubbleContent
        }
    }

    @ViewBuilder
    private var mainBubbleContent: some View {
        HStack {
            if role == .user { Spacer() }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    // Thinking section
                    if hasThinking {
                        MessageThinkingSection(
                            thinking: displayThinking,
                            isStreaming: isStreaming,
                            isFinished: isThinkingFinished,
                            isExpanded: $isThinkingExpanded,
                            hasContent: hasContent
                        )
                    }

                    // Main content
                    if hasContent {
                        if role == .tool {
                            MessageToolResultView(
                                content: message?.content ?? "",
                                isExpanded: $isToolResultExpanded,
                                contentBody: AnyView(contentBody)
                            )
                        } else {
                            contentBody
                        }
                    }

                    // Tool Calls
                    if let toolCalls = message?.toolCalls, !toolCalls.isEmpty {
                        if hasContent {
                            Divider().padding(.horizontal, 8).opacity(0.2)
                        }
                        MessageToolCallsSection(toolCalls: toolCalls, isExpanded: $isToolCallsExpanded)
                    }

                    if isStreaming && !hasThinking && !hasContent {
                        loadingState
                    }
                }
                .background(backgroundColor)
                .foregroundColor(textColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isStreaming ? Color.blue.opacity(0.1) : Color.clear, lineWidth: 1)
                )

                MessageMetadataSection(
                    message: message,
                    isStreaming: isStreaming,
                    role: role,
                    showingDebugInfo: $showingDebugInfo
                )
            }

            if role == .assistant { Spacer() }
        }
        .onAppear {
            if isStreaming {
                if !streamingThinking.isEmpty { isThinkingExpanded = true }
                isToolCallsExpanded = true
            }
        }
        .contextMenu { contextMenuContent }
        .sheet(isPresented: $showingDebugInfo) {
            if let message = message {
                MessageDebugView(message: message, debugInfo: message.debugInfo ?? MessageDebugInfo())
            }
        }
        .sheet(isPresented: $showingSubagentInfo) {
            if let context = message?.subagentContext {
                SubagentContextView(context: context)
            }
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Monad is thinking...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var contentBody: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attributedString(from: displayContent))
                    .background(Color.clear)
                    .textSelection(.enabled)

                if message?.subagentContext != nil {
                    subagentBling
                }
            }
            .padding(12)

            if isStreaming {
                cursor
            }
        }
    }

    @ViewBuilder
    private var subagentBling: some View {
        Button(action: { showingSubagentInfo = true }) {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                Text("Subagent Context")
            }
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .foregroundColor(.purple)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var cursor: some View {
        Text("▋")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.blue)
            .padding(.bottom, 12)
            .padding(.trailing, 8)
            .opacity(0.7)
            .modifier(BlinkingModifier())
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let message = message {
            if message.role == .user || message.role == .assistant {
                Button("Show Debug Info") { showingDebugInfo = true }
            }

            Button("Copy Content") {
                #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                #else
                    UIPasteboard.general.string = message.content
                #endif
            }
        }
    }

    // MARK: - Helpers

    private var role: Message.MessageRole {
        message?.role ?? .assistant
    }

    private var hasThinking: Bool {
        if isStreaming { return !streamingThinking.isEmpty }
        return message?.think != nil && !(message?.think?.isEmpty ?? true)
    }

    private var isThinkingFinished: Bool {
        !isStreaming || !streamingContent.isEmpty || (message?.toolCalls?.isEmpty == false)
    }

    private var displayThinking: String {
        isStreaming ? streamingThinking : (message?.think ?? "")
    }

    private var hasContent: Bool {
        if isStreaming { return !streamingContent.isEmpty }
        return message?.content.isEmpty == false
    }

    private var displayContent: String {
        if isStreaming {
            let toolCallPattern = Regex {
                Optionally {
                    "```"
                    Optionally("xml")
                    ZeroOrMore(.whitespace)
                }
                "<tool_call>"
                ZeroOrMore(.any, .reluctant)
                "</tool_call>"
                Optionally {
                    ZeroOrMore(.whitespace)
                    "```"
                }
            }
            .dotMatchesNewlines()

            let openToolCallPattern = Regex {
                "<tool_call>"
                ZeroOrMore(.any)
            }
            .dotMatchesNewlines()

            return streamingContent
                .replacing(toolCallPattern, with: "")
                .replacing(openToolCallPattern, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if role == .assistant {
            return message?.displayContent ?? ""
        } else {
            return message?.content ?? ""
        }
    }

    private func attributedString(from markdown: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(markdown)
        }
    }

    private var backgroundColor: Color {
        if isStreaming { return Color.gray.opacity(0.15) }
        switch role {
        case .user: return Color.blue
        case .assistant: return Color.gray.opacity(0.2)
        case .system: return Color.orange.opacity(0.2)
        case .tool: return Color.purple.opacity(0.1)
        case .summary: return Color.yellow.opacity(0.1)
        }
    }

    private var textColor: Color {
        if isStreaming { return .primary }
        switch role {
        case .user: return .white
        case .assistant, .system, .tool, .summary: return .primary
        }
    }
}