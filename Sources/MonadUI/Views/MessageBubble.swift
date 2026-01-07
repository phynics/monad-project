import MonadCore
import SwiftUI
import RegexBuilder
import MarkdownUI

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
    @State private var showingDebugInfo = false
    @State private var showingSubagentInfo = false
    @State private var selectedMemory: Memory?
    @State private var selectedDocument: DocumentContext?

    public init(message: Message) {
        self.message = message
        self.isStreaming = false
        self.streamingThinking = ""
        self.streamingContent = ""
    }

    public init(streamingThinking: String, streamingContent: String) {
        self.message = nil
        self.isStreaming = true
        self.streamingThinking = streamingThinking
        self.streamingContent = streamingContent
    }

    public var body: some View {
        if message?.isSummary == true {
            HStack {
                Spacer()
                Text(message?.content ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.vertical, 4)
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
                            HStack(alignment: .bottom, spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Markdown(displayContent)
                                        .markdownTheme(.gitHub)
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

                                    // Context section for user messages
                                    if let memories = message?.recalledMemories, !memories.isEmpty {
                                        FlowLayout(spacing: 4) {
                                            ForEach(memories) { memory in
                                                Button(action: { selectedMemory = memory }) {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "brain.head.profile")
                                                            .font(.system(size: 7))
                                                        Text(memory.title)
                                                            .font(.system(size: 8, weight: .bold))
                                                            .lineLimit(1)
                                                    }
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(role == .user ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                                                    .foregroundColor(role == .user ? .white : .blue)
                                                    .cornerRadius(4)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }

                                    if let docs = message?.recalledDocuments, !docs.isEmpty {
                                        FlowLayout(spacing: 4) {
                                            ForEach(docs) { doc in
                                                Button(action: { selectedDocument = doc }) {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "doc.text.fill")
                                                            .font(.system(size: 7))
                                                        Text(doc.path.split(separator: "/").last?.description ?? doc.path)
                                                            .font(.system(size: 8, weight: .bold))
                                                            .lineLimit(1)
                                                    }
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(role == .user ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                                                    .foregroundColor(role == .user ? .white : .blue)
                                                    .cornerRadius(4)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.top, 2)
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

                        // Tool Calls
                        if let toolCalls = message?.toolCalls, !toolCalls.isEmpty {
                            if hasContent {
                                Divider().padding(.horizontal, 8).opacity(0.2)
                            }

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
                                                    .lineLimit(1)
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

                        if let tags = message?.tags, !tags.isEmpty {
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
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
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
            .sheet(item: $selectedDocument) { doc in
                DocumentContextDetailView(document: doc)
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
        return message?.displayContent ?? ""
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

// Subagent Context View
struct SubagentContextView: View {
    let context: SubagentContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Prompt") {
                    Text(context.prompt)
                        .font(.body)
                }
                
                Section("Documents") {
                    if context.documents.isEmpty {
                        Text("No documents")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(context.documents, id: \.self) { path in
                            HStack {
                                Image(systemName: "doc.text")
                                Text(path)
                            }
                        }
                    }
                }
                
                if let raw = context.rawResponse {
                    Section("Raw Output") {
                        Text(raw)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
            .navigationTitle("Subagent Context")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Document Context Detail View
struct DocumentContextDetailView: View {
    let document: DocumentContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Path") {
                    Text(document.path)
                        .font(.body)
                        .monospaced()
                }
                
                Section("Status") {
                    LabeledContent("View Mode", value: document.viewMode.rawValue.capitalized)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(document.fileSize), countStyle: .file))
                    if document.viewMode == .excerpt {
                        LabeledContent("Offset", value: "\(document.excerptOffset)")
                        LabeledContent("Length", value: "\(document.excerptLength)")
                    }
                    LabeledContent("Pinned", value: document.isPinned ? "Yes" : "No")
                }
                
                if let summary = document.summary {
                    Section("Summary") {
                        Text(summary)
                            .font(.body)
                    }
                }
                
                Section("Content (\(document.viewMode.rawValue.capitalized))") {
                    Text(document.visibleContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Document Context")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
