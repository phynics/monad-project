import OSLog

/// Parser for streaming LLM responses with Chain of Thought support
///
/// Handles streaming responses that contain `<think>...</think>` blocks,
/// separating reasoning from main content in real-time.
/// Parser for streaming LLM responses with Chain of Thought support
public class StreamingParser {
    private var buffer = ""
    private var thinkingBuffer = ""
    private var contentBuffer = ""
    private var insideThinkTag = false
    private var insideCodeBlock = false
    private var rawBuffer = ""  // Keep original for debugging

    public init() {}

    /// - Returns: Tuple with updated thinking and content (only new text since last call) and a flag indicating if state was reclassified
    public func process(_ chunk: String) -> (
        thinking: String?, content: String?, isReclassified: Bool
    ) {
        buffer += chunk
        rawBuffer += chunk  // Keep raw for debugging

        var isReclassified = false

        Logger.parser.debug(
            "Processing chunk: '\(chunk, privacy: .public)' (total buffer: \(self.buffer.count) chars)"
        )

        var newThinking: String?
        var newContent: String?

        // Debug: Show chunk if it contains tag-related content
        if chunk.contains("<think") || chunk.contains("</think") || chunk.contains("think>") {
            Logger.parser.info("[Parser] Chunk with tag content: '\(chunk, privacy: .public)'")
        }

        // Debug: Check if we're seeing think tags in full buffer
        if buffer.contains("<think>") {
            Logger.parser.debug("[Parser] Buffer contains <think> tag")
        }
        if buffer.contains("</think>") {
            Logger.parser.debug("[Parser] Buffer contains </think> tag")
        }

        // Process buffer to extract thinking and content
        while let result = processBuffer() {
            if result.isThinking {
                Logger.parser.debug(
                    "[Parser] EXTRACTED THINKING: \(result.text.count) chars: '\(result.text)'")
                thinkingBuffer += result.text
                newThinking = (newThinking ?? "") + result.text
            } else {
                Logger.parser.debug(
                    "[Parser] EXTRACTED CONTENT: \(result.text.count) chars: '\(result.text)'")

                // Workaround: If we find a </think> tag but we weren't inside one,
                // it means we missed the opening <think> tag.
                if result.text.contains("RECLASSIFY_THINKING_MARKER") {
                    Logger.parser.warning(
                        "[Parser] ORPHANED </think> DETECTED! Reclassifying accumulated content.")
                    let actualText = result.text.replacingOccurrences(
                        of: "RECLASSIFY_THINKING_MARKER", with: "")

                    // Prepend all previous content to thinking
                    thinkingBuffer = contentBuffer + actualText
                    contentBuffer = ""
                    isReclassified = true

                    // Reset new outputs as we want the UI to replace everything
                    newThinking = thinkingBuffer
                    newContent = ""
                } else {
                    contentBuffer += result.text
                    newContent = (newContent ?? "") + result.text
                }
            }
        }

        return (newThinking, newContent, isReclassified)
    }

    /// Get final thinking and content after stream completes
    /// - Returns: Complete thinking (optional) and content strings
    public func finalize() -> (thinking: String?, content: String) {
        print("[Parser] Finalizing - buffer: '\(buffer.prefix(100))'")
        print("[Parser] Raw buffer length: \(rawBuffer.count)")
        print("[Parser] Thinking buffer length: \(thinkingBuffer.count)")
        print("[Parser] Content buffer length: \(contentBuffer.count)")
        print("[Parser] Inside think tag: \(insideThinkTag)")

        // Process any remaining buffer
        if !buffer.isEmpty {
            if insideThinkTag {
                print("[Parser] Adding remaining buffer to thinking")
                thinkingBuffer += buffer
            } else {
                print("[Parser] Adding remaining buffer to content")
                contentBuffer += buffer
            }
            buffer = ""
        }

        let finalThinking =
            thinkingBuffer.isEmpty
            ? nil : thinkingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = contentBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Parser] Final thinking: \(finalThinking?.count ?? 0) chars")
        print("[Parser] Final content: \(finalContent.count) chars")

        return (finalThinking, finalContent)
    }

    /// Reset parser state for new message
    public func reset() {
        buffer = ""
        thinkingBuffer = ""
        contentBuffer = ""
        insideThinkTag = false
        insideCodeBlock = false
        rawBuffer = ""
    }

    // MARK: - Private Methods

    private func processBuffer() -> (text: String, isThinking: Bool)? {
        // Detect markdown code blocks to avoid misparsing tags inside them
        if let codeBlockRange = buffer.range(of: "```") {
            let textBefore = String(buffer[..<codeBlockRange.lowerBound])
            buffer.removeSubrange(..<codeBlockRange.upperBound)
            insideCodeBlock.toggle()

            if !textBefore.isEmpty {
                return (textBefore, insideThinkTag)
            }
            // Add back the backticks as regular text to be processed
            let backticks = "```"
            return (backticks, insideThinkTag)
        }

        if insideThinkTag {
            // Look for closing </think> tag
            if !insideCodeBlock, let endRange = buffer.range(of: "</think>") {
                Logger.parser.info("[Parser] Found closing </think> tag! Exiting thinking mode")
                let text = String(buffer[..<endRange.lowerBound])
                buffer.removeSubrange(..<endRange.upperBound)
                insideThinkTag = false
                return (text, true)
            }

            // Look for any '<' that might be the start of a </think> tag
            if !insideCodeBlock, let lastAngleBracket = buffer.lastIndex(of: "<") {
                let potentialTag = String(buffer[lastAngleBracket...])

                // If it looks like it could be </think>, don't flush it yet
                if "</think>".hasPrefix(potentialTag) {
                    if lastAngleBracket > buffer.startIndex {
                        let safeContent = String(buffer[..<lastAngleBracket])
                        buffer = potentialTag
                        Logger.parser.debug(
                            "[Parser] Flushing thinking before potential tag: '\(potentialTag, privacy: .public)'"
                        )
                        return (safeContent, true)
                    }
                    // Buffer is just the partial tag, wait for more
                    Logger.parser.debug(
                        "[Parser] Holding partial tag: '\(potentialTag, privacy: .public)'")
                    return nil
                }
            }

            // Large buffer safety (though unlikely in streams)
            if buffer.count > 1000 {
                Logger.parser.warning(
                    "[Parser] Large buffer in thinking mode (\(self.buffer.count) chars), potential missing tag"
                )
            }

            // No partial </think> tag at the end, safe to flush all current buffer as thinking
            if !buffer.isEmpty {
                let text = buffer
                buffer = ""
                return (text, true)
            }
            return nil
        } else {
            // Look for opening <think> tag
            if !insideCodeBlock, let startRange = buffer.range(of: "<think>") {
                Logger.parser.info("[Parser] Found opening <think> tag! Entering thinking mode")
                // Extract content before <think> tag
                let textBefore = String(buffer[..<startRange.lowerBound])
                buffer.removeSubrange(..<startRange.upperBound)
                insideThinkTag = true

                if !textBefore.isEmpty {
                    Logger.parser.debug(
                        "[Parser] Returning content before tag: \(textBefore.count) chars")
                    return (textBefore, false)
                }
                // Continue processing for thinking content
                return processBuffer()
            }

            // Look for any '<' that might be the start of a tag
            if !insideCodeBlock, let lastAngleBracket = buffer.lastIndex(of: "<") {
                let potentialTag = String(buffer[lastAngleBracket...])

                // Check if this might be start of <think>
                if "<think>".hasPrefix(potentialTag) {
                    // Partial tag - flush content before '<', keep potential tag
                    if lastAngleBracket > buffer.startIndex {
                        let safeContent = String(buffer[..<lastAngleBracket])
                        buffer = potentialTag
                        Logger.parser.debug(
                            "[Parser] Flushing content before potential tag: '\(potentialTag, privacy: .public)'"
                        )
                        return (safeContent, false)
                    }
                    // Buffer is just the partial tag, wait for more
                    Logger.parser.debug(
                        "[Parser] Holding potential tag start: '\(potentialTag, privacy: .public)'"
                    )
                    return nil
                }

                // ORPHANED TAG DETECTION: Check if this might be start of </think>
                // even though we aren't "inside" one
                if "</think>".hasPrefix(potentialTag) {
                    if lastAngleBracket > buffer.startIndex {
                        let safeContent = String(buffer[..<lastAngleBracket])
                        buffer = potentialTag
                        Logger.parser.debug(
                            "[Parser] Flushing content before potential orphaned tag: '\(potentialTag, privacy: .public)'"
                        )
                        return (safeContent, false)
                    }
                    Logger.parser.debug(
                        "[Parser] Holding potential orphaned tag start: '\(potentialTag, privacy: .public)'"
                    )
                    return nil
                }
            }

            // ORPHANED TAG DETECTION: Look for full </think> tag even when not insideThinkTag
            if !insideCodeBlock, let endRange = buffer.range(of: "</think>") {
                Logger.parser.warning(
                    "[Parser] Found orphaned </think> tag! Triggering reclassification.")
                let textBefore = String(buffer[..<endRange.lowerBound])
                buffer.removeSubrange(..<endRange.upperBound)
                // We don't set insideThinkTag to true because we just hit the end of it
                return (textBefore + "RECLASSIFY_THINKING_MARKER", false)
            }

            // No '<' in buffer, safe to flush everything
            if !buffer.isEmpty {
                let text = buffer
                buffer = ""
                return (text, false)
            }
        }

        return nil
    }

    // MARK: - Tool Call Parsing

    /// Extract tool calls from text containing XML tags
    /// - Parameter text: Input text
    /// - Returns: Tuple of clean text (tags removed) and extracted tool calls
    func extractToolCalls(from text: String) -> (cleanText: String, toolCalls: [ToolCall]) {
        var cleanText = text
        var toolCalls: [ToolCall] = []

        // Match <tool_call>...</tool_call> blocks, optionally wrapped in markdown code blocks
        // The pattern handles:
        // 1. Optional opening code fence (e.g. ```xml)
        // 2. The <tool_call>...</tool_call> block
        // 3. Optional closing code fence (```)
        // We use non-greedy matching .*? for content
        let pattern = "(?:```(?:xml)?\\s*)?<tool_call>(.*?)</tool_call>(?:\\s*```)?"

        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else {
            return (text, [])
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        // Iterate matches in reverse to replace content without messing up ranges
        for match in matches.reversed() {
            let fullRange = match.range
            // Group 1 captures the content inside <tool_call>...</tool_call>
            let contentRange = match.range(at: 1)

            let jsonString = nsString.substring(with: contentRange).trimmingCharacters(
                in: .whitespacesAndNewlines)

            if let jsonData = jsonString.data(using: .utf8),
                let toolCall = try? JSONDecoder().decode(ToolCall.self, from: jsonData)
            {
                toolCalls.append(toolCall)
            } else {
                Logger.parser.error("Failed to parse tool call JSON: \(jsonString)")
            }

            // Remove the tool call block (including surrounding code blocks) from the text
            cleanText = (cleanText as NSString).replacingCharacters(in: fullRange, with: "")
        }

        // Reverse tool calls to restore original order (since we processed matches in reverse)
        toolCalls.reverse()

        return (cleanText, toolCalls)
    }
}
