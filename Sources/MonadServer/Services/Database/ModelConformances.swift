import Foundation
import GRDB
import MonadCore
import MonadShared

// MARK: - Persistence Error

public enum PersistenceError: LocalizedError {
    case invalidUUIDFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidUUIDFormat(let value):
            return "Invalid UUID format: \(value)"
        }
    }
}

// MARK: - ConversationMessage

extension ConversationMessage: FetchableRecord, PersistableRecord {
    // Default Codable implementation
}

// MARK: - ConversationSession

extension ConversationSession: FetchableRecord, PersistableRecord {
    // Default Codable implementation
}

// MARK: - Job

extension Job: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "job" }
}

// MARK: - Agent

extension Agent: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "agent" }
}

extension Agent {
    /// Helper to fetch the default agent from the database
    public static func fetchDefault(in db: Database) throws -> Agent? {
        return try Agent.fetchOne(db, key: "default")
    }
}

// MARK: - WorkspaceTool

extension WorkspaceTool: FetchableRecord, PersistableRecord {
    // Default Codable implementation
}

// MARK: - Memory

extension Memory: FetchableRecord, PersistableRecord {
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
                    let formatted = "\(nsString.substring(with: match.range(at: 1)))-\(nsString.substring(with: match.range(at: 2)))-\(nsString.substring(with: match.range(at: 3)))-\(nsString.substring(with: match.range(at: 4)))-\(nsString.substring(with: match.range(at: 5)))"
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
            title: row["title"],
            content: row["content"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"],
            tags: row["tags"],
            metadata: row["metadata"],
            embedding: row["embedding"]
        )
    }
}
