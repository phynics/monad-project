import Foundation
import OSLog

extension Logger {
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.monad.assistant"
    }

    /// Logs related to the UI view layer
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logs related to data persistence and database operations
    public static let database = Logger(subsystem: subsystem, category: "database")

    /// Logs related to LLM services and networking
    public static let llm = Logger(subsystem: subsystem, category: "llm")

    /// Logs related to chat coordination and logic
    public static let chat = Logger(subsystem: subsystem, category: "chat")

    /// Logs related to tool execution
    public static let tools = Logger(subsystem: subsystem, category: "tools")

    /// Logs related to general app lifecycle and configuration
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// Logs related to the standalone server
    public static let server = Logger(subsystem: subsystem, category: "server")

    /// Logs related to streaming response parsing
    public static let parser = Logger(subsystem: subsystem, category: "parser")
}
