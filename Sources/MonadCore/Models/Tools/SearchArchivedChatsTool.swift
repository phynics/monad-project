import Foundation

/// Tool to search archived conversations
public final class SearchArchivedChatsTool: Tool, Sendable {
    public let id = "search_archived_chats"
    public let name = "Search Archived Chats"
    public let description = "Search through archived conversation history to find past discussions"
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {"name": "search_archived_chats", "arguments": {"query": "SwiftUI architecture"}}
        </tool_call>
        """
    }

    private let persistenceService: PersistenceService

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description":
                        "Search query to find in archived conversations (searches title and message content)",
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of tags to filter by",
                ],
            ],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let query = parameters["query"] as? String
        let tags = parameters["tags"] as? [String]

        if query == nil && (tags == nil || tags!.isEmpty) {
            return .failure("Either 'query' or 'tags' must be provided.")
        }

        do {
            var allSessions: [ConversationSession] = []

            if let query = query, !query.isEmpty {
                allSessions = try await persistenceService.searchArchivedSessions(query: query)
            }

            if let tags = tags, !tags.isEmpty {
                let tagSessions = try await persistenceService.searchArchivedSessions(
                    matchingAnyTag: tags)
                let existingIds = Set(allSessions.map { $0.id })
                for session in tagSessions {
                    if !existingIds.contains(session.id) {
                        allSessions.append(session)
                    }
                }
            }

            if allSessions.isEmpty {
                let criteria = [
                    query != nil ? "query '\(query!)'" : nil, tags != nil ? "tags \(tags!)" : nil,
                ]
                .compactMap { $0 }.joined(separator: " and ")
                return .success("No archived conversations found matching \(criteria)")
            }

            let results: String = allSessions.prefix(10).map { session in
                let tagsStr =
                    session.tagArray.isEmpty
                    ? "" : " [Tags: \(session.tagArray.joined(separator: ", "))]"
                return
                    "- \(session.title)\(tagsStr) [ID: \(session.id.uuidString)] (Updated: \(session.updatedAt.formatted()))"
            }.joined(separator: "\n")

            return .success(
                "Found \(allSessions.count) archived conversation(s):\n\(results)\n\nTo read a conversation, use 'load_archived_chat' with the provided ID."
            )
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}
