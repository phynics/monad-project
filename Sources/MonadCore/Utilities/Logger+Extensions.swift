import Foundation
import Logging

extension Logger {
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.monad.assistant"
    }

    /// Logs related to the UI view layer
    public static let ui = Logger(label: "\(subsystem).ui")

    /// Logs related to data persistence and database operations
    public static let database = Logger(label: "\(subsystem).database")

    /// Logs related to LLM services and networking
    public static let llm = Logger(label: "\(subsystem).llm")

    /// Logs related to chat coordination and logic
    public static let chat = Logger(label: "\(subsystem).chat")

    /// Logs related to tool execution
    public static let tools = Logger(label: "\(subsystem).tools")

    /// Logs related to general app lifecycle and configuration
    public static let app = Logger(label: "\(subsystem).app")

    /// Logs related to the standalone server
    public static let server = Logger(label: "\(subsystem).server")

    /// Logs related to streaming response parsing
    public static let parser = Logger(label: "\(subsystem).parser")

    /// Logs related to client operations
    public static let client = Logger(label: "\(subsystem).client")
}
