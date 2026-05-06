import PositronicKit

enum MonadSystemInstructions {
    private static let sharedPrefix = "You are PositronicKit, an intelligent developer assistant."
    private static let monadPrefix = "You are Monad, an intelligent developer assistant."

    static func system() -> String {
        DefaultInstructions.system().replacingOccurrences(of: sharedPrefix, with: monadPrefix)
    }
}
