import Foundation
import OSLog

/// Strategy for context compression
public enum CompressionScope: String, Sendable, CustomStringConvertible {
    /// Summarize messages into individual topics based on group size or markers.
    case topic
    /// Force a broad summary that collapses all existing topic summaries into one.
    case broad
    
    public var description: String { rawValue }
}

/// Service to compress conversation context using summarization
public actor ContextCompressor {
    private let llmService: any LLMServiceProtocol
    private let logger = Logger(subsystem: "com.monad.core", category: "ContextCompressor")
    
    // Configuration
    private let topicGroupSize = 10 // Messages per topic chunk
    private let recentMessageBuffer = 10 // Keep last N messages raw
    private let broadSummaryThreshold = 2000 // Tokens before triggering broad summary
    
    public init(llmService: any LLMServiceProtocol) {
        self.llmService = llmService
    }
    
    /// Compress the message history by summarizing older messages
    ///
    /// Strategy:
    /// 1. Keep the most recent `recentMessageBuffer` messages raw.
    /// 2. Group the older messages into chunks of `topicGroupSize`.
    /// 3. Summarize each chunk into a single `.summary` message.
    /// 4. If the total token count of summaries exceeds `broadSummaryThreshold` (or scope is .broad), collapse them into a "Broad Summary".
    public func compress(messages: [Message], scope: CompressionScope = .topic) async throws -> [Message] {
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
                summaryContent = await generateSummary(for: chunk)
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
        // Calculate total tokens in the compressed history
        let totalTokens = compressedHistory.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
        
        // If we exceed the threshold OR scope is .broad, collapse everything into one Broad Summary
        if (totalTokens > broadSummaryThreshold || scope == .broad) && compressedHistory.count > 1 {
            let broadSummaryContent = await generateBroadSummary(from: compressedHistory)
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
    
    /// Chunk messages based on explicit topic change markers or max size
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
    
    private func generateSummary(for messages: [Message]) async -> String {
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
    
    private func generateBroadSummary(from summaries: [Message]) async -> String {
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

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}