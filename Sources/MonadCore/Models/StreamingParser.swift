import OSLog

/// Parser for streaming LLM responses with Chain of Thought support
///
/// Handles streaming responses that contain `<think>...</think>` blocks,
/// separating reasoning from main content in real-time.
public class StreamingParser {
    // MARK: - State
    private var buffer = ""
    private var thinkingBuffer = ""
    private var contentBuffer = ""
    
    private var insideThinkTag = false
    private var insideCodeBlock = false
    
    private var rawBuffer = ""  // Debug history

    public init() {}

    // MARK: - Public API

    /// Process a new text chunk
    /// - Returns: Tuple with new thinking text, new content text, and reclassification flag
    public func process(_ chunk: String) -> (
        thinking: String?, content: String?, isReclassified: Bool
    ) {
        buffer += chunk
        rawBuffer += chunk

        var isReclassified = false
        var newThinking: String?
        var newContent: String?

        // Process buffer exhaustively
        while let result = extractNextSegment() {
            if result.isThinking {
                thinkingBuffer += result.text
                newThinking = (newThinking ?? "") + result.text
            } else {
                // Check for orphaned closing tag marker
                if result.text.contains("RECLASSIFY_THINKING_MARKER") {
                    Logger.parser.warning("[Parser] ORPHANED </think> DETECTED! Reclassifying.")
                    let actualText = result.text.replacingOccurrences(
                        of: "RECLASSIFY_THINKING_MARKER", with: "")
                    
                    // Move all previous content to thinking
                    thinkingBuffer = contentBuffer + actualText
                    contentBuffer = ""
                    isReclassified = true
                    
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

    /// Finalize parsing and return complete buffers
    public func finalize() -> (thinking: String?, content: String) {
        // Flush remaining buffer
        if !buffer.isEmpty {
            if insideThinkTag {
                thinkingBuffer += buffer
            } else {
                contentBuffer += buffer
            }
            buffer = ""
        }

        let finalThinking = thinkingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = contentBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (finalThinking.isEmpty ? nil : finalThinking, finalContent)
    }

    /// Reset parser state
    public func reset() {
        buffer = ""
        thinkingBuffer = ""
        contentBuffer = ""
        insideThinkTag = false
        insideCodeBlock = false
        rawBuffer = ""
    }

    // MARK: - Core Parsing Logic

    /// Extracts the next valid text segment from the buffer, updating state
    private func extractNextSegment() -> (text: String, isThinking: Bool)? {
        guard !buffer.isEmpty else { return nil }

        // 1. Check for Code Block Delimiters ("```")
        // We prioritize this to prevent parsing tags inside code blocks
        if let range = buffer.range(of: "```") {
            let prefix = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            insideCodeBlock.toggle()
            
            // Return text before delimiter with *previous* state
            if !prefix.isEmpty {
                return (prefix, insideThinkTag)
            }
            // Return the delimiter itself
            return ("```", insideThinkTag)
        }
        
        // 2. Hold Partial Code Delimiters
        // If buffer ends with "`" or "``", wait for more data to ensure we don't miss a block toggle.
        // Unless the buffer is getting dangerously large.
        if buffer.count < 1000 && (buffer.hasSuffix("``") || buffer.hasSuffix("`")) {
            return nil
        }
        
        // 3. Handle Tags (Only if NOT inside a code block)
        if !insideCodeBlock {
            if insideThinkTag {
                // Looking for closing </think>
                if let range = buffer.range(of: "</think>") {
                    let content = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(..<range.upperBound)
                    insideThinkTag = false
                    return (content, true)
                }
                
                // Check for partial closing tag at end
                if let start = buffer.lastIndex(of: "<") {
                    let suffix = buffer[start...]
                    if "</think>".hasPrefix(String(suffix)) {
                        // Return safe content before tag
                        if start > buffer.startIndex {
                            let content = String(buffer[..<start])
                            buffer = String(suffix)
                            return (content, true)
                        }
                        return nil // Wait for full tag
                    }
                }
            } else {
                // Looking for opening <think>
                if let range = buffer.range(of: "<think>") {
                    let content = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(..<range.upperBound)
                    insideThinkTag = true
                    
                    if !content.isEmpty {
                        return (content, false)
                    }
                    // Recursively process immediately to handle content inside the tag
                    return extractNextSegment()
                }
                
                // Check for partial opening tag at end
                if let start = buffer.lastIndex(of: "<") {
                    let suffix = buffer[start...]
                    // Check for <think>
                    if "<think>".hasPrefix(String(suffix)) {
                        if start > buffer.startIndex {
                            let content = String(buffer[..<start])
                            buffer = String(suffix)
                            return (content, false)
                        }
                        return nil
                    }
                    // Check for orphaned </think> (partial)
                    if "</think>".hasPrefix(String(suffix)) {
                        if start > buffer.startIndex {
                            let content = String(buffer[..<start])
                            buffer = String(suffix)
                            return (content, false)
                        }
                        return nil
                    }
                }
                
                // Check for full orphaned closing tag (Reclassify Workaround)
                if let range = buffer.range(of: "</think>") {
                    let content = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(..<range.upperBound)
                    return (content + "RECLASSIFY_THINKING_MARKER", false)
                }
            }
        }
        
        // 4. Flush Remaining Buffer
        // If we reached here, no full tags/blocks were found.
        // And we already checked for partials at the end.
        // So safe to flush everything.
        let text = buffer
        buffer = ""
        return (text, insideThinkTag)
    }

    // MARK: - Tool Parsing

    /// Extract tool calls from text containing XML tags
    func extractToolCalls(from text: String) -> (cleanText: String, toolCalls: [ToolCall]) {
        var cleanText = text
        var toolCalls: [ToolCall] = []

        // Pattern handles optional code fences around <tool_call>
        let pattern = "(?:```(?:xml)?\\s*)?<tool_call>(.*?)</tool_call>(?:\\s*```)?"

        guard let regex = try? NSRegularExpression(
            pattern: pattern, 
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return (text, []) }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        // Process in reverse to preserve ranges during replacement
        for match in matches.reversed() {
            let fullRange = match.range
            let contentRange = match.range(at: 1)
            
            let jsonString = nsString.substring(with: contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = jsonString.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: jsonData) {
                toolCalls.append(toolCall)
            } else {
                Logger.parser.error("Failed to parse tool call JSON: \(jsonString)")
            }

            cleanText = (cleanText as NSString).replacingCharacters(in: fullRange, with: "")
        }

        return (cleanText, toolCalls.reversed())
    }
}
