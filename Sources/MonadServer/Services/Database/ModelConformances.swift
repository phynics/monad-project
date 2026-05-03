import ErrorKit
import Foundation
import GRDB
import PositronicKit
import PKShared
import MonadShared

// MARK: - Persistence Error

public enum PersistenceError: PKError {
    case invalidUUIDFormat(String)

    public var errorDomain: String { PKErrorDomain.persistence }

    public var errorCode: Int {
        switch self {
        case .invalidUUIDFormat: return 1201
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .invalidUUIDFormat:
            return "A record in the database has an invalid identifier format."
        }
    }
}

// MARK: - ConversationMessage

extension ConversationMessage: @retroactive FetchableRecord, @retroactive PersistableRecord {
    // Default Codable implementation
}

// MARK: - Timeline

extension Timeline: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String {
        "timeline"
    }
}

// MARK: - AgentTemplate

extension AgentTemplate: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String {
        "agent"
    }
}

public extension AgentTemplate {
    /// Helper to fetch the default agent from the database
    static func fetchDefault(in db: Database) throws -> AgentTemplate? {
        return try AgentTemplate.fetchOne(db, key: "default")
    }
}

// MARK: - Memory

extension Memory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public init(row: Row) throws {
        // Handle ID decoding with fallback for non-hyphenated UUID strings
        let id: UUID
        if let uuid = row["id"] as? UUID {
            id = uuid
        } else if let uuidString = row["id"] as? String {
            if let uuid = UUID(uuidString: uuidString) {
                id = uuid
            } else {
                // Try inserting hyphens for raw hex string (8-4-4-4-12)
                let pattern = "([0-9a-fA-F]{8})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{12})"
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(uuidString.startIndex..., in: uuidString)
                if let match = regex.firstMatch(in: uuidString, range: range) {
                    let nsString = uuidString as NSString
                    let parts = (1 ... 5).map {
                        nsString.substring(with: match.range(at: $0))
                    }
                    let formatted = parts.joined(separator: "-")
                    if let uuid = UUID(uuidString: formatted) {
                        id = uuid
                    } else {
                        throw PersistenceError.invalidUUIDFormat(uuidString)
                    }
                } else {
                    throw PersistenceError.invalidUUIDFormat(uuidString)
                }
            }
        } else {
            // Try standard decoding which handles data blobs
            id = row["id"]
        }

        self.init(
            id: id,
            title: row["title"] as String,
            content: row["content"] as String,
            createdAt: row["createdAt"] as Date,
            updatedAt: row["updatedAt"] as Date,
            tags: row["tags"] as String,
            metadata: row["metadata"] as String,
            embedding: row["embedding"] as String
        )
    }
}
