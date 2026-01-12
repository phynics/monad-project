import Foundation
import GRDB

public struct TableDirectoryEntry: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let createdAt: Date
    
    public static let databaseTableName = "table_directory"
}
