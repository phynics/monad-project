import Foundation
import Dependencies
import Logging

/// Utility to validate that critical dependencies are configured before use.
public struct DependencyValidator: Sendable {
    private let logger = Logger.module(named: "dependency-validator")

    public init() {}

    /// Validates that all required core dependencies are configured.
    /// Returns true if all critical dependencies are present, false otherwise.
    public func validateRequired() async -> Bool {
        @Dependency(\.persistenceService) var persistence
        @Dependency(\.llmService) var llm
        @Dependency(\.embeddingService) var embedding

        var missing: [String] = []

        if persistence is UnconfiguredPersistenceService { missing.append("PersistenceService") }
        if llm is UnconfiguredLLMService { missing.append("LLMService") }
        if embedding is UnconfiguredEmbeddingService { missing.append("EmbeddingService") }

        if !missing.isEmpty {
            logger.error("Missing critical dependencies: \(missing.joined(separator: ", ")). Did you call MonadCore.configure()?")
            return false
        }

        return true
    }
}
