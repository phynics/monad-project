import ErrorKit
import MonadShared
import Foundation

public enum WorkspaceToolError: Throwable {
    case missingDefinition

    public var errorDescription: String? {
        switch self {
        case .missingDefinition:
            return "Missing workspace tool definition."
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .missingDefinition:
            return "The workspace tool's configuration is incomplete."
        }
    }
}
