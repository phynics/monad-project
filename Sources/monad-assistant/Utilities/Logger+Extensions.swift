import Foundation
import os.log

extension Logger {
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.monad.assistant"
    }

    /// Logs related to the UI view layer
    static let view = Logger(subsystem: subsystem, category: "view")

    /// Logs related to data persistence and database operations
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Logs related to LLM services and networking
    static let llm = Logger(subsystem: subsystem, category: "llm")

    /// Logs related to chat coordination and logic
    static let chat = Logger(subsystem: subsystem, category: "chat")

    /// Logs related to tool execution
    static let tools = Logger(subsystem: subsystem, category: "tools")

    /// Logs related to general app lifecycle and configuration
    static let app = Logger(subsystem: subsystem, category: "app")
}
