import Foundation
import GRDB

// MARK: - Workspace Trust Level

public enum WorkspaceTrustLevel: String, Codable, Sendable, DatabaseValueConvertible {
    case full  // Unrestricted within boundary
    case restricted  // Allowlist of operations
}
