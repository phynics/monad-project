import Dependencies
import Foundation

// MARK: - Dependency Keys

public enum LLMServiceKey: DependencyKey {
    public static let liveValue: any LLMServiceProtocol = {
        fatalError("LLMService must be configured before use.")
    }()
}

public enum EmbeddingServiceKey: DependencyKey {
    public static let liveValue: any EmbeddingServiceProtocol = {
        fatalError("EmbeddingService must be configured before use.")
    }()
}

// MARK: - Dependency Values

extension DependencyValues {
    public var llmService: any LLMServiceProtocol {
        get { self[LLMServiceKey.self] }
        set { self[LLMServiceKey.self] = newValue }
    }

    public var embeddingService: any EmbeddingServiceProtocol {
        get { self[EmbeddingServiceKey.self] }
        set { self[EmbeddingServiceKey.self] = newValue }
    }
}
