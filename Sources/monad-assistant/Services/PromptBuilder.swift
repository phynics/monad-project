import Foundation
import OpenAI

/// Extensible prompt building system with token management
///
/// Plug & play system - add components, they're automatically formatted and optimized.
actor PromptBuilder {
    // Token limits (rough estimates for common models)
    private let maxContextTokens: Int
    private let reserveTokensForResponse: Int

    init(maxContextTokens: Int = 120000, reserveTokensForResponse: Int = 8000) {
        self.maxContextTokens = maxContextTokens
        self.reserveTokensForResponse = reserveTokensForResponse
    }

    /// Build a complete prompt with all components
    /// - Parameters:
    ///   - systemInstructions: Base system instructions (defaults to built-in)
    ///   - contextNotes: Always-append notes
    ///   - tools: Available tools
    ///   - chatHistory: Previous messages in conversation
    ///   - userQuery: Current user message
    /// - Returns: Tuple of (messages for LLM, debug raw prompt string)
    func buildPrompt(
        systemInstructions: String? = nil,
        contextNotes: [Note],
        tools: [Tool] = [],
        chatHistory: [Message],
        userQuery: String
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], rawPrompt: String) {

        // Build components in priority order
        var components: [any PromptSection] = []

        // System instructions (use default if not provided)
        let instructions = systemInstructions ?? DefaultInstructions.system
        components.append(SystemInstructionsComponent(instructions: instructions))

        // Context notes
        if !contextNotes.isEmpty {
            components.append(ContextNotesComponent(notes: contextNotes))
        }

        // Tools
        if !tools.isEmpty {
            components.append(ToolsComponent(tools: tools))
        }

        // Chat history
        components.append(ChatHistoryComponent(messages: chatHistory))

        // User query
        components.append(UserQueryComponent(query: userQuery))

        // Sort by priority
        components.sort { $0.priority > $1.priority }

        // Generate content and optimize
        let (systemContent, historyMessages) = await generateContent(
            from: components, chatHistory: chatHistory)

        // Build OpenAI messages
        let messages = await buildMessages(
            systemContent: systemContent, history: historyMessages, userQuery: userQuery)

        // Generate debug prompt
        let rawPrompt = await generateDebugPrompt(components: components, chatHistory: chatHistory)

        return (messages, rawPrompt)
    }

    /// Generate human-readable raw prompt for debugging
    private func generateDebugPrompt(
        components: [any PromptSection],
        chatHistory: [Message]
    ) async -> String {
        var sections: [String] = []

        for component in components {
            if component.sectionId == "chat_history" {
                if !chatHistory.isEmpty {
                    let history = chatHistory.map { msg in
                        "[\(msg.role.rawValue.uppercased())] \(msg.content)"
                    }.joined(separator: "\n\n")
                    sections.append("=== CHAT HISTORY ===\n\(history)")
                }
            } else if let content = await component.generateContent() {
                sections.append("=== \(component.sectionId.uppercased()) ===\n\(content)")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Content Generation

    private func generateContent(
        from components: [any PromptSection],
        chatHistory: [Message]
    ) async -> (systemContent: String, historyMessages: [Message]) {
        var systemParts: [String] = []

        // Generate content for each component
        for component in components {
            if component.sectionId == "chat_history" {
                // History handled separately
                continue
            }

            if component.sectionId == "user_query" {
                // User query is added as a separate message
                continue
            }

            if let content = await component.generateContent() {
                systemParts.append(content)
            }
        }

        let systemContent = systemParts.joined(separator: "\n\n---\n\n")

        // Optimize history if needed
        let optimizedHistory = await optimizeHistory(
            chatHistory, availableTokens: maxContextTokens - estimateTokens(systemContent))

        return (systemContent, optimizedHistory)
    }

    private func buildMessages(
        systemContent: String,
        history: [Message],
        userQuery: String
    ) async -> [ChatQuery.ChatCompletionMessageParam] {
        var messages: [ChatQuery.ChatCompletionMessageParam] = []

        // System message
        if !systemContent.isEmpty {
            messages.append(.system(.init(content: .textContent(systemContent), name: nil)))
        }

        // History
        for msg in history {
            switch msg.role {
            case .user:
                messages.append(.user(.init(content: .string(msg.content), name: nil)))
            case .assistant:
                var content = msg.content
                if let think = msg.think {
                    content = "<think>\(think)</think>\n\(content)"
                }
                messages.append(
                    .assistant(.init(content: .textContent(content), name: nil, toolCalls: nil)))
            case .system:
                // Skip - already in system message
                continue
            case .tool:
                // Tool responses are formatted as user messages with <tool_response> tags
                messages.append(
                    .user(
                        .init(
                            content: .string("<tool_response>\n\(msg.content)\n</tool_response>"),
                            name: nil)))
            }
        }

        // User query
        if !userQuery.isEmpty {
            messages.append(.user(.init(content: .string(userQuery), name: nil)))
        }

        return messages
    }

    // MARK: - Token Management

    private func estimateTokens(_ text: String) -> Int {
        TokenEstimator.estimate(text: text)
    }

    private func optimizeHistory(_ messages: [Message], availableTokens: Int) async -> [Message] {
        var result: [Message] = []
        var usedTokens = 0

        // Keep most recent messages
        for message in messages.reversed() {
            let tokens = estimateTokens(message.content)
            if usedTokens + tokens <= availableTokens {
                result.insert(message, at: 0)
                usedTokens += tokens
            } else {
                // Add summary if we truncated
                if result.count < messages.count {
                    let summary = Message(
                        content: "[Earlier: \(messages.count - result.count) messages]",
                        role: .system
                    )
                    result.insert(summary, at: 0)
                }
                break
            }
        }

        return result
    }

}
