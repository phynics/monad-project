import Foundation
import Logging

// MARK: - Configuration

/// Root configuration object for Monad.
public struct Configuration: Codable, Sendable, Equatable {
    public var llm: LLMConfiguration
    
    public init(llm: LLMConfiguration = .init()) {
        self.llm = llm
    }
    
    public static var `default`: Configuration {
        Configuration(llm: .init())
    }
    
    /// Validates the entire configuration.
    /// Throws ``ConfigurationError`` if any setting is invalid.
    public func validate() throws {
        try llm.validate()
    }
}

// MARK: - Errors

public enum ConfigurationError: LocalizedError {
    case invalidConfiguration(reason: String)
    case missingAPIKey(LLMProvider)
    case invalidEndpoint(String)
    case noBackupFound
    case importFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .missingAPIKey(let provider):
            return "Missing API key for provider: \(provider.rawValue)"
        case .invalidEndpoint(let endpoint):
            return "Invalid endpoint URL: \(endpoint)"
        case .noBackupFound:
            return "No backup configuration found"
        case .importFailed:
            return "Failed to import configuration: Invalid format"
        }
    }
}
