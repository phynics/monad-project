import Foundation
import GRDB

// MARK: - Workspace Host Type

public enum WorkspaceHostType: String, Codable, Sendable, DatabaseValueConvertible {
    case client
    case server
}
