import MonadCore
import SwiftUI
import RegexBuilder

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
        if message?.isSummary == true {
            if message?.summaryType == .broad {
                // Broad Summary: Gray middle blob
                Button(action: { withAnimation { isSummaryExpanded.toggle() } }) {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text(isSummaryExpanded ? (message?.content ?? "") : "Broad Summary")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if !isSummaryExpanded {
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            } else {
                // Topic Summary: Vertical line on left
                Button(action: { withAnimation { isSummaryExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 4)
                            .cornerRadius(2)
                            .padding(.vertical, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Topic Summary")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.secondary)
                            
                            if isSummaryExpanded {
                                Text(message?.content ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(message?.content ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        } else {
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
                                        .padding(.bottom, 2)
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
                            if role == .tool {
                                VStack(alignment: .leading, spacing: 0) {
                                    Button(action: { withAnimation { isToolResultExpanded.toggle() } }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: isToolResultExpanded ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 8))
                                            Image(systemName: "terminal")
                                                .font(.system(size: 9))
                                            Text("Tool Result (\(message?.content.count ?? 0) chars)")
                                                .font(.system(size: 10, weight: .bold))
                                            Spacer()
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if isToolResultExpanded || (message?.content.count ?? 0) <= 300 {
                                        if isToolResultExpanded {
                                            Divider().padding(.horizontal, 8).opacity(0.1)
                                        }
                                        contentBody
                                    } else {
                                        // Collapsed long result preview
                                        Text(message?.content ?? "")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .padding(.horizontal, 12)
                                            .padding(.bottom, 8)
                                            .opacity(0.7)
                                    }
                                }
                            } else {
                                contentBody
                            }
                        }

                        // Tool Calls
                        if let toolCalls = message?.toolCalls, !toolCalls.isEmpty {
                            if hasContent {
                                Divider().padding(.horizontal, 8).opacity(0.2)
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: { withAnimation { isToolCallsExpanded.toggle() } }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isToolCallsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 8))
                                        Image(systemName: "wrench.and.screwdriver.fill")
                                            .font(.system(size: 9))
                                        Text("Tool Calls (\(toolCalls.count))")
                                            .font(.system(size: 10, weight: .bold))
                                        Spacer()
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isToolCallsExpanded {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(toolCalls) { toolCall in
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Image(systemName: "wrench.and.screwdriver.fill")
                                                        .font(.caption)
                                                    Text("Tool Used: \(toolCall.name)")
                                                        .font(.caption)
                                                        .bold()
                                                }

                                                if !toolCall.arguments.isEmpty {
                                                    ForEach(
                                                        toolCall.arguments.sorted(by: { $0.key < $1.key }),
                                                        id: \.key
                                                    ) { key, value in
                                                        Text("\(key): \(String(describing: value))")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .monospaced()
                                                    }
                                                    .padding(.leading, 20)
                                                }
                                                
                                                // UI Bling: Show in Finder for filesystem paths
                                                if (toolCall.name == "ls" || toolCall.name == "find"),
                                                   let path = toolCall.arguments["path"]?.value as? String {
                                                    Button(action: {
                                                        #if os(macOS)
                                                        let url = URL(fileURLWithPath: path)
                                                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                                                        #endif
                                                    }) {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "folder.fill")
                                                            Text("Show in Finder")
                                                        }
                                                        .font(.caption2)
                                                        .foregroundColor(.blue)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .padding(.leading, 20)
                                                    .padding(.top, 4)
                                                }
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
                            }
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

                    // Tags and Stats (Under the bubble)
                    HStack(spacing: 4) {
                        if role == .user, let progress = message?.gatheringProgress, progress != .complete {
                            Button {
                                showingDebugInfo = true
                            } label: {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.3)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(progress.rawValue)
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .textCase(.uppercase)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        if let tags = message?.tags, !tags.isEmpty {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    showingDebugInfo = true
                                } label: {
                                    Text("#\(tag)")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    if let stats = message?.stats, (stats.tokensPerSecond != nil || stats.totalTokens != nil) {
                        HStack(spacing: 8) {
                            if let tps = stats.tokensPerSecond {
                                Text(String(format: "%.1f tokens/sec", tps))
                            }
                            if let total = stats.totalTokens {
                                Text("\(total) tokens")
                            }
                            
                            if role == .assistant && message?.debugInfo != nil {
                                Button {
                                    showingDebugInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    }

                    if let timestamp = message?.timestamp {
                        Text(timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
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
            .onAppear {
                if isStreaming {
                    if !streamingThinking.isEmpty {
                        isThinkingExpanded = true
                    }
                    isToolCallsExpanded = true
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
                        #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        #else
                            UIPasteboard.general.string = message.content
                        #endif
                    }
                }
            }
            .sheet(isPresented: $showingDebugInfo) {
                if let message = message, let debugInfo = message.debugInfo {
                    MessageDebugView(message: message, debugInfo: debugInfo)
                }
            }
            .sheet(isPresented: $showingSubagentInfo) {
                if let context = message?.subagentContext {
                    SubagentContextView(context: context)
                }
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attributedString(from: displayContent))
                    .background(Color.clear)
                    .textSelection(.enabled)
                
                // Subagent Context Bling
                if let _ = message?.subagentContext {
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
            }
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
        !isStreaming || !streamingContent.isEmpty || (message?.toolCalls?.isEmpty == false)
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
        if isStreaming {
            // Regex for <tool_call>...content...</tool_call>
            // Handling potential code blocks around it
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
            
            // Regex for open <tool_call>... (at the end)
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
        
        // ONLY strip tool calls for assistant role. 
        // Tool role messages might contain content we want to see (like subagent results).
        if role == .assistant {
            return message?.displayContent ?? ""
        } else {
            return message?.content ?? ""
        }
    }

    private func attributedString(from markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(markdown)
        }
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
        case .summary:
            return Color.yellow.opacity(0.1)
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
        case .summary:
            return .primary
        }
    }
}