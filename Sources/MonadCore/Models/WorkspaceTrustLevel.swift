import Foundation

// MARK: - Workspace Trust Level

public enum WorkspaceTrustLevel: String, Codable, Sendable {
    case full  // Unrestricted within boundary
    case restricted  // Allowlist of operations
}
