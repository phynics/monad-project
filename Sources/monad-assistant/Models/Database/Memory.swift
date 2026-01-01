import Foundation
import GRDB

/// Searchable memory item for storing knowledge
struct Memory: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var tags: String  // JSON array stored as string
    var metadata: String  // JSON object stored as string
    
    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = (try? JSONEncoder().encode(tags).base64EncodedString()) ?? ""
        self.metadata = (try? JSONEncoder().encode(metadata).base64EncodedString()) ?? ""
    }
    
    var tagArray: [String] {
        guard let data = Data(base64Encoded: tags),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
    
    var metadataDict: [String: String] {
        guard let data = Data(base64Encoded: metadata),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
}

// MARK: - Prompt Formatting

extension Memory: PromptFormattable {
    /// Formatted content for inclusion in LLM prompt
    var promptString: String {
        var parts: [String] = []
        
        // Title
        parts.append("**\(title)**")
        
        // Tags (if present)
        let tags = tagArray
        if !tags.isEmpty {
            parts.append("_Tags: \(tags.joined(separator: ", "))_")
        }
        
        // Content
        parts.append(content)
        
        return parts.joined(separator: "\n")
    }
}

extension Array where Element == Memory {
    /// Format multiple memories for prompt inclusion
    var promptContent: String {
        guard !isEmpty else { return "" }
        
        return """
        # Memories
        
        \(map { $0.promptString }.joined(separator: "\n\n"))
        """
    }
}
