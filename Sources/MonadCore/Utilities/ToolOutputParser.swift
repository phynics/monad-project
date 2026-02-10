import Foundation

/// Utility for parsing tool calls from raw text content when structured tool calls fail.
public struct ToolOutputParser {
    
    /// Represents a parsed tool call
    public struct FallbackToolCall: Codable {
        public let name: String
        public let arguments: [String: AnyCodable]
        
        // Internal helper for decoding flexibility
        private struct RawCall: Codable {
            let tool: String?
            let name: String?
            let args: [String: AnyCodable]?
            let arguments: [String: AnyCodable]?
            
            var resolvedName: String? { tool ?? name }
            var resolvedArgs: [String: AnyCodable]? { args ?? arguments }
        }
        
        public init(from decoder: Decoder) throws {
            let raw = try RawCall(from: decoder)
            guard let name = raw.resolvedName, let args = raw.resolvedArgs else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required tool name or arguments"))
            }
            self.name = name
            self.arguments = args
        }
    }

    /// Attempts to parse a tool call from a string that might contain JSON code blocks.
    /// - Parameter content: The raw text content from the LLM.
    /// - Returns: A FallbackToolCall object if successful, nil otherwise.
    public static func parse(from content: String) -> FallbackToolCall? {
        // 1. Clean content
        var cleaned = content
        
        // A. Check for XML-style <tool_call> tags
        // Simple regex to extract content between tags
        if let regex = try? NSRegularExpression(pattern: "(?s)<tool_call>(.*?)</tool_call>", options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            cleaned = String(content[range])
        }
        // B. Check for markdown code blocks
        else if let range = cleaned.range(of: "```json", options: .caseInsensitive),
           let endRange = cleaned.range(of: "```", options: .backwards) {
            if range.upperBound < endRange.lowerBound {
                cleaned = String(cleaned[range.upperBound..<endRange.lowerBound])
            }
        } else if let range = cleaned.range(of: "```", options: .caseInsensitive), // Generic code block
                  let endRange = cleaned.range(of: "```", options: .backwards) {
            if range.upperBound < endRange.lowerBound {
                cleaned = String(cleaned[range.upperBound..<endRange.lowerBound])
            }
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else { return nil }
        
        // 2. Try to decode
        guard let data = cleaned.data(using: .utf8) else { return nil }
        
        // Handle array of tools (take first) or single object
        if cleaned.hasPrefix("[") {
            if let calls = try? JSONDecoder().decode([FallbackToolCall].self, from: data),
               let first = calls.first {
                return first
            }
        } else {
             if let call = try? JSONDecoder().decode(FallbackToolCall.self, from: data) {
                return call
            }
        }
        
        return nil
    }
}
