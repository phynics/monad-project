import Foundation
import OpenAI
import MonadPrompt
import MonadShared

extension Prompt {
    /// Convert the assembled prompt into OpenAI chat messages
    public func toMessages() async -> [ChatQuery.ChatCompletionMessageParam] {
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        var systemParts: [String] = []
        
        // 1. Collect System Context (System, Notes, Memories, Tools)
        // We iterate sections in priority order (Prompt sorts them).
        // Standard sections render headers like "# System Instructions" or "=== MEMORY CONTEXT ===".
        
        for section in sections {
            // History and UserQuery are handled separately as proper chat messages
            if section.id == "chat_history" || section.id == "user_query" { continue }
            
            if let content = await section.render(), !content.isEmpty {
                systemParts.append(content)
            }
        }
        
        if !systemParts.isEmpty {
            let combinedSystem = systemParts.joined(separator: "\n\n---\n\n")
            messages.append(.system(.init(content: .textContent(combinedSystem), name: nil)))
        }
        
        // 2. Chat History
        if let historySection = sections.first(where: { $0.id == "chat_history" }) as? ChatHistory {
            for msg in historySection.messages {
                switch msg.role {
                case .user:
                    messages.append(.user(.init(content: .string(msg.content), name: nil)))
                    
                case .assistant:
                    var content = msg.content
                    if let think = msg.think {
                        content = "<think>\(think)</think>\n\(content)"
                    }
                    
                    var toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]?
                    if let calls = msg.toolCalls, !calls.isEmpty {
                        toolCalls = calls.map { call in
                            .init(
                                id: call.id.uuidString,
                                function: .init(
                                    arguments: (try? call.arguments.toJsonString()) ?? "{}",
                                    name: call.name
                                )
                            )
                        }
                    }
                    
                    messages.append(.assistant(.init(content: .textContent(content), name: nil, toolCalls: toolCalls)))
                    
                case .system:
                    messages.append(.system(.init(content: .textContent(msg.content), name: nil)))
                    
                case .tool:
                    // Tool responses are formatted as user messages with <tool_response> tags
                    let hiddenInstruction = "\n[System: This is a system message hidden from user; now respond to the user about this result.]"
                    let content = "<tool_response>\n\(msg.content)\n</tool_response>\(hiddenInstruction)"
                    messages.append(.user(.init(content: .string(content), name: nil)))
                    
                case .summary:
                    messages.append(.system(.init(content: .textContent(msg.content), name: nil)))
                }
            }
        }
        
        // 3. User Query
        if let querySection = sections.first(where: { $0.id == "user_query" }),
           let content = await querySection.render() {
            messages.append(.user(.init(content: .string(content), name: nil)))
        }
        
        return messages
    }
}
