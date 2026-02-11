import Foundation
import Logging

/// Strategy for context compression
public enum CompressionScope: String, Sendable, CustomStringConvertible {
    /// Summarize messages into individual topics based on group size or markers.
    case topic
    /// Force a broad summary that collapses all existing topic summaries into one.
    case broad
    
    public var description: String { rawValue }
}

/// Recursive node structure for Raptor-style summarization
public enum ConversationNode: Sendable {
    case leaf(Message)
    case summary(content: String, children: [ConversationNode])

    var content: String {
        switch self {
        case .leaf(let msg): return msg.content
        case .summary(let text, _): return text
        }
    }

    var tokens: Int {
        TokenEstimator.estimate(text: content)
    }
}

/// Service to compress conversation context using summarization
public actor ContextCompressor {
    private let logger = Logger(label: "com.monad.ContextCompressor")
    
    // Configuration
    private let topicGroupSize = 10 // Messages per topic chunk
    private let recentMessageBuffer = 10 // Keep last N messages raw
    private let broadSummaryThreshold = 2000 // Tokens before triggering broad summary
    
    public init() {}

    // MARK: - Legacy Compression (Topic/Broad)
    
    /// Compress the message history by summarizing older messages
    public func compress(
        messages: [Message],
        scope: CompressionScope = .topic,
        llmService: any LLMServiceProtocol
    ) async throws -> [Message] {
        guard messages.count > recentMessageBuffer else {
            return messages
        }
        
        let splitIndex = messages.count - recentMessageBuffer
        let olderMessages = Array(messages.prefix(splitIndex))
        let recentMessages = Array(messages.suffix(from: splitIndex))
        
        // Chunk older messages based on topic markers or size
        let chunks = smartChunk(messages: olderMessages)
        var compressedHistory: [Message] = []
        
        for chunk in chunks {
            // Check if this chunk is already a single summary?
            if chunk.count == 1, chunk[0].role == .summary {
                compressedHistory.append(chunk[0])
                continue
            }
            
            // Check if the chunk contains a topic change tool call with a provided summary
            var providedSummary: String?
            for msg in chunk {
                if let calls = msg.toolCalls,
                   let call = calls.first(where: { $0.name == "mark_topic_change" }),
                   let summary = call.arguments["summary"]?.value as? String {
                    providedSummary = summary
                    break
                }
            }
            
            let summaryContent: String
            if let provided = providedSummary {
                summaryContent = provided
            } else {
                summaryContent = await generateSummary(for: chunk, llmService: llmService)
            }
            
            let summaryNode = Message(
                content: summaryContent,
                role: .summary,
                isSummary: true,
                summaryType: .topic
            )
            compressedHistory.append(summaryNode)
        }
        
        // Secondary Compression: "Broad Summary"
        let totalTokens = TokenEstimator.estimate(parts: compressedHistory.map(\.content))
        
        if (totalTokens > broadSummaryThreshold || scope == .broad) && compressedHistory.count > 1 {
            let broadSummaryContent = await generateBroadSummary(from: compressedHistory, llmService: llmService)
            let broadSummaryNode = Message(
                content: broadSummaryContent,
                role: .summary,
                isSummary: true,
                summaryType: .broad
            )
            return [broadSummaryNode] + recentMessages
        }
        
        return compressedHistory + recentMessages
    }
    
    // MARK: - Raptor / Recursive Compression

    /// Recursively summarize messages to fit within a target token count
    public func recursiveSummarize(
        messages: [Message],
        targetTokens: Int,
        llmService: any LLMServiceProtocol
    ) async -> [Message] {
        // 1. First pass: Collapse tool interactions to save space cheaply
        let collapsedMessages = summarizeToolInteractions(in: messages)

        let currentTokens = TokenEstimator.estimate(parts: collapsedMessages.map(\.content))
        if currentTokens <= targetTokens {
            return collapsedMessages
        }

        // 2. Separate recent messages (preserve them)
        let safeBuffer = min(recentMessageBuffer, collapsedMessages.count)
        let splitIndex = collapsedMessages.count - safeBuffer

        let olderMessages = Array(collapsedMessages.prefix(splitIndex))
        let recentMessages = Array(collapsedMessages.suffix(from: splitIndex))

        if olderMessages.isEmpty {
            return recentMessages
        }

        // 3. Recursive summarization of older messages
        // Convert to nodes
        var nodes: [ConversationNode] = olderMessages.map { .leaf($0) }

        // Loop until we fit or can't compress further
        var iterations = 0
        let maxIterations = 5

        while iterations < maxIterations {
            let currentOlderTokens = nodes.reduce(0) { $0 + $1.tokens }
            let availableForOlder = max(0, targetTokens - TokenEstimator.estimate(parts: recentMessages.map(\.content)))

            if currentOlderTokens <= availableForOlder {
                break
            }

            // Chunk nodes and summarize
            nodes = await summarizeLevel(nodes: nodes, llmService: llmService)
            iterations += 1
        }

        // 4. Flatten back to Messages
        let summarizedHistory = nodes.map { node -> Message in
            switch node {
            case .leaf(let msg): return msg
            case .summary(let content, _):
                return Message(
                    content: content,
                    role: .summary,
                    isSummary: true,
                    summaryType: .topic
                )
            }
        }

        return summarizedHistory + recentMessages
    }

    /// Summarize a list of memories into a single narrative
    public func summarizeMemories(
        _ memories: [Memory],
        targetTokens: Int,
        llmService: any LLMServiceProtocol
    ) async -> String {
        guard !memories.isEmpty else { return "" }

        let rawContent = memories.promptContent
        if TokenEstimator.estimate(text: rawContent) <= targetTokens {
            return rawContent
        }

        // Simple chunking and summarizing
        let chunks = memories.chunked(into: 10)
        var summaries: [String] = []

        for chunk in chunks {
            let chunkText = chunk.map { "- \($0.content)" }.joined(separator: "\n")
            let prompt = """
            Compress the following user memories into a single concise paragraph. Preserve key facts, names, and preferences.

            MEMORIES:
            \(chunkText)
            """

            do {
                let summary = try await llmService.sendMessage(prompt, responseFormat: nil, useUtilityModel: true)
                summaries.append(summary)
            } catch {
                summaries.append(chunkText)
            }
        }

        let combined = summaries.joined(separator: "\n\n")

        // If still too big, one final pass
        if TokenEstimator.estimate(text: combined) > targetTokens {
             let prompt = """
            Create a high-level summary of the user's memory context.

            CONTEXT:
            \(combined)
            """
             do {
                 return try await llmService.sendMessage(prompt, responseFormat: nil, useUtilityModel: true)
             } catch {
                 return combined
             }
        }

        return combined
    }

    // MARK: - Tool Interaction Collapsing

    /// Collapses tool call -> tool response pairs into a single summary message
    /// Logic:
    /// - Scans for Assistant (w/ ToolCalls) -> Tool (result) sequences.
    /// - Keeps recent interactions raw (for context continuity).
    /// - Collapses older completed interactions.
    public func summarizeToolInteractions(in messages: [Message]) -> [Message] {
        guard messages.count > recentMessageBuffer else { return messages }

        let splitIndex = messages.count - recentMessageBuffer
        let olderMessages = Array(messages.prefix(splitIndex))
        let recentMessages = Array(messages.suffix(from: splitIndex))

        var processed: [Message] = []
        var i = 0

        while i < olderMessages.count {
            let msg = olderMessages[i]

            // Check for tool call
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                // Look ahead for tool results
                var interactionNodes: [Message] = [msg]
                var j = i + 1


                // Expect a tool message for each tool call
                // Note: Messages might be interleaved or sequential.
                // Simple heuristic: Collect subsequent .tool messages until we hit a user/assistant message or run out

                while j < olderMessages.count {
                    let next = olderMessages[j]
                    if next.role == .tool {
                        interactionNodes.append(next)
                        j += 1
                    } else {
                        break
                    }
                }

                // Verify we have results? (Optional, but strictness helps)
                // For now, if we found *any* tool results, we collapse.
                if interactionNodes.count > 1 {
                    let summary = Message(
                        content: "[Tool Interaction: \(toolCalls.map { $0.name }.joined(separator: ", ")) executed. Results hidden.]",
                        role: .summary,
                        isSummary: true
                    )
                    processed.append(summary)
                    i = j
                    continue
                }
            }

            processed.append(msg)
            i += 1
        }

        return processed + recentMessages
    }

    // MARK: - Internal Helpers

    private func summarizeLevel(nodes: [ConversationNode], llmService: any LLMServiceProtocol) async -> [ConversationNode] {
        // Group nodes into chunks (e.g. 5 nodes or ~1000 tokens)
        var newNodes: [ConversationNode] = []
        var currentChunk: [ConversationNode] = []
        var currentTokens = 0
        let maxChunkTokens = 2000

        for node in nodes {
            let tokens = node.tokens
            if currentTokens + tokens > maxChunkTokens && !currentChunk.isEmpty {
                // Process chunk
                let summaryNode = await summarizeChunk(currentChunk, llmService: llmService)
                newNodes.append(summaryNode)
                currentChunk = []
                currentTokens = 0
            }
            currentChunk.append(node)
            currentTokens += tokens
        }

        if !currentChunk.isEmpty {
            if currentChunk.count == 1 {
                newNodes.append(currentChunk[0]) // Don't re-summarize a single node
            } else {
                let summaryNode = await summarizeChunk(currentChunk, llmService: llmService)
                newNodes.append(summaryNode)
            }
        }

        return newNodes
    }

    private func summarizeChunk(_ nodes: [ConversationNode], llmService: any LLMServiceProtocol) async -> ConversationNode {
        let transcript = nodes.map { $0.content }.joined(separator: "\n\n")
        let prompt = """
        Summarize the following conversation segment. Capture the key points, user intent, and outcomes.

        TRANSCRIPT:
        \(transcript)
        """

        do {
            let summary = try await llmService.sendMessage(prompt, responseFormat: nil, useUtilityModel: true)
            return .summary(content: summary, children: nodes)
        } catch {
            logger.error("Recursive summary failed")
            return .summary(content: "Summary failed.", children: nodes)
        }
    }

    private func smartChunk(messages: [Message]) -> [[Message]] {
        var chunks: [[Message]] = []
        var currentChunk: [Message] = []
        
        for (index, msg) in messages.enumerated() {
            currentChunk.append(msg)
            
            // Check if this message initiated a topic change
            let hasTopicChangeSignal = msg.toolCalls?.contains { $0.name == "mark_topic_change" } ?? false
            
            // Optimization: Avoid breaking tool sequences (Call -> Result)
            // If current message is a tool call, we should try to include the next message if it's a result.
            let isToolCall = msg.toolCalls != nil && !msg.toolCalls!.isEmpty
            var shouldDeferChunking = false
            if isToolCall && index + 1 < messages.count {
                let nextMsg = messages[index + 1]
                if nextMsg.role == .tool {
                    shouldDeferChunking = true
                }
            }
            
            if hasTopicChangeSignal {
                chunks.append(currentChunk)
                currentChunk = []
            } else if currentChunk.count >= topicGroupSize && !shouldDeferChunking {
                // Fallback limit
                chunks.append(currentChunk)
                currentChunk = []
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
    
    private func generateSummary(for messages: [Message], llmService: any LLMServiceProtocol) async -> String {
        let transcript = messages.map { "[\($0.role.rawValue.uppercased())] \($0.content)" }.joined(separator: "\n")
        let prompt = """
        Summarize the following discussion topic concisely (max 100 words). Focus on key decisions, technical details, and outcomes.
        
        TRANSCRIPT:
        \(transcript)
        """
        
        do {
            let summary = try await llmService.sendMessage(prompt, responseFormat: nil, useUtilityModel: true)
            return summary
        } catch {
            logger.error("Failed to generate summary: \(error.localizedDescription)")
            return "Topic Summary (Generation Failed): \(messages.count) messages."
        }
    }
    
    private func generateBroadSummary(from summaries: [Message], llmService: any LLMServiceProtocol) async -> String {
        let transcript = summaries.map { $0.content }.joined(separator: "\n\n")
        let prompt = """
        Create a high-level "Broad Summary" of the conversation so far, based on the following topic summaries.
        The goal is to compress context while retaining the overall narrative arc and critical facts.
        
        TOPIC SUMMARIES:
        \(transcript)
        """
        
        do {
            let summary = try await llmService.sendMessage(prompt, responseFormat: nil, useUtilityModel: true)
            return summary
        } catch {
            logger.error("Failed to generate broad summary: \(error.localizedDescription)")
            return "Broad Conversation Summary (Generation Failed)."
        }
    }
}
