import Foundation
import MonadPrompt
import MonadShared

/// Events emitted during prompt assembly.
public enum PromptAssemblyEvent: Sendable {
    case stageStarted(String)
    case stageCompleted(String)
}

/// Manages prompt assembly state. Pipeline-ready.
public actor PromptAssemblyContext: Sendable {
    public let request: LLMPromptRequest
    public let agentInstance: AgentInstance?
    public let timeline: Timeline?
    public let extensionSections: [any ContextSection]
    public private(set) var sections: [any ContextSection] = []

    public init(
        request: LLMPromptRequest,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil,
        extensionSections: [any ContextSection] = []
    ) {
        self.request = request
        self.agentInstance = agentInstance
        self.timeline = timeline
        self.extensionSections = extensionSections
    }

    public func append(_ section: any ContextSection) {
        sections.append(section)
    }

    public func append(_ sections: [any ContextSection]) {
        self.sections.append(contentsOf: sections)
    }
}

/// A specialized pipeline for prompt assembly.
public typealias PromptAssemblyPipeline = Pipeline<PromptAssemblyContext, PromptAssemblyEvent>

/// Protocol defining a single stage in the prompt assembly pipeline.
public protocol PromptAssemblyStage: PipelineStage where Context == PromptAssemblyContext, Event == PromptAssemblyEvent {}

public extension PromptAssemblyStage {
    /// Default implementation returns the type name.
    var id: String {
        String(describing: Self.self)
    }

    /// Helper to execute an action and yield start/complete events.
    func running(_ context: PromptAssemblyContext, action: @Sendable () async throws -> Void) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        let id = self.id
        try await action()
        return AsyncThrowingStream { continuation in
            continuation.yield(.stageStarted(id))
            continuation.yield(.stageCompleted(id))
            continuation.finish()
        }
    }
}

/// DSL for composing prompt assembly stages.
@resultBuilder
public struct PromptAssemblyBuilder {
    public static func buildExpression(_ expression: any ContextSection) -> [any ContextSection] { [expression] }
    public static func buildExpression(_ expression: [any ContextSection]) -> [any ContextSection] { expression }
    public static func buildBlock(_ components: [any ContextSection]...) -> [any ContextSection] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [any ContextSection]?) -> [any ContextSection] { component ?? [] }
    public static func buildEither(first component: [any ContextSection]) -> [any ContextSection] { component }
    public static func buildEither(second component: [any ContextSection]) -> [any ContextSection] { component }
    public static func buildArray(_ components: [[any ContextSection]]) -> [any ContextSection] { components.flatMap { $0 } }
}
