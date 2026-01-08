import Foundation
import OSLog
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Tool to create a new memory
public final class CreateMemoryTool: Tool, @unchecked Sendable {
    public let id = "create_memory"
    public let name = "Create Memory"
    public let description = "Create a new memory entry to remember important information"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "create_memory", "arguments": {"title": "User Preference", "content": "User prefers \\"dark mode\\" and \\"Swift\\" for development tasks.", "tags": ["preferences"]}}
        </tool_call>
        """
    }

    private let persistenceService: PersistenceService
    private let embeddingService: any EmbeddingService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.monad.shared", category: "CreateMemoryTool")

    public init(persistenceService: PersistenceService, embeddingService: any EmbeddingService) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Title of the memory",
                ],
                "content": [
                    "type": "string",
                    "description": "Content to remember",
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional tags for categorization. If not provided, keywords will be extracted automatically.",
                ],
            ],
            "required": ["title", "content"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let title = parameters["title"] as? String,
            let content = parameters["content"] as? String
        else {
            let errorMsg = "Missing required parameters: title and content."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }

        var tags = parameters["tags"] as? [String] ?? []
        
        // Auto-generate tags if none provided
        if tags.isEmpty {
            tags = extractKeywords(from: "\(title) \(content)")
        }
        
        logger.info("Creating memory: \(title) with \(tags.count) tags")

        do {
            // Generate embedding
            let embedding = try await embeddingService.generateEmbedding(for: "\(title)\n\(content)")
            
            let memory = Memory(
                title: title,
                content: content,
                tags: tags,
                embedding: embedding
            )

            try await persistenceService.saveMemory(memory)
            logger.info("Successfully created memory: \(title)")
            return .success("Memory '\(title)' created successfully with semantic embedding and \(tags.count) tags.")
        } catch {
            logger.error("Failed to create memory: \(error.localizedDescription)")
            return .failure("Failed to create memory: \(error.localizedDescription)")
        }
    }
    
    private func extractKeywords(from text: String) -> [String] {
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let tags = tagger.tags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options)
        
        let keywords = tags.compactMap { (tag, range) -> String? in
            guard let tag = tag else { return nil }
            // Extract nouns and proper nouns as keywords
            if tag == .noun || tag == .otherWord {
                let word = String(text[range]).lowercased()
                return word.count > 3 ? word : nil
            }
            return nil
        }
        
        // Return unique keywords, limited to top 5
        return Array(Set(keywords)).sorted().prefix(5).map { String($0) }
        #else
        return []
        #endif
    }
}
