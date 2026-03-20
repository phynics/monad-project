import Foundation
import MonadPrompt
import MonadShared

/// Events emitted during prompt assembly.
public enum PromptAssemblyEvent: Sendable {
    /// Indicates a stage has started processing.
    case stageStarted(String)
    /// Indicates a stage has completed processing.
    case stageCompleted(String)
}

/// Manages prompt assembly state. Pipeline-ready.
public actor PromptAssemblyContext: Sendable {
    /// The original prompt request.
    public let request: LLMPromptRequest
    /// The agent instance associated with the prompt.
    public let agentInstance: AgentInstance?
    /// The conversation timeline.
    public let timeline: Timeline?
    /// Additional context sections provided by extensions.
    public let extensionSections: [any ContextSection]
    /// The gathered prompt sections.
    public private(set) var sections: [any ContextSection] = []

    /// Initializes a new prompt assembly context.
    /// - Parameters:
    ///   - request: The prompt request data.
    ///   - agentInstance: Optional agent instance.
    ///   - timeline: Optional timeline.
    ///   - extensionSections: Optional extension sections.
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

    /// Appends a single section to the prompt.
    /// - Parameter section: The section to add.
    public func append(_ section: any ContextSection) {
        sections.append(section)
    }

    /// Appends multiple sections to the prompt.
    /// - Parameter sections: The sections to add.
    public func append(_ sections: [any ContextSection]) {
        self.sections.append(contentsOf: sections)
    }
}

/// A specialized pipeline for prompt assembly.
public typealias PromptAssemblyPipeline = Pipeline<PromptAssemblyContext, PromptAssemblyEvent>

/// Protocol defining a single stage in the prompt assembly pipeline.
public protocol PromptAssemblyStage: PipelineStage where Context == PromptAssemblyContext, Event == PromptAssemblyEvent {
    /// Executes the assembly logic for this stage.
    func execute(_ context: PromptAssemblyContext) async throws
}

public extension PromptAssemblyStage {
    /// Default implementation returns the type name.
    var id: String {
        String(describing: Self.self)
    }

    /// Default implementation of process that wraps execute in start/complete events.
    func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            try await execute(context)
        }
    }

    /// Helper to execute an action and yield start/complete events.
    /// - Parameters:
    ///   - context: The shared assembly context.
    ///   - action: The work to perform.
    /// - Returns: A stream that yields start and complete events.
    func running(_: PromptAssemblyContext, action: @escaping @Sendable () async throws -> Void) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        let id = self.id
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.stageStarted(id))
                do {
                    try await action()
                    continuation.yield(.stageCompleted(id))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

/// DSL for composing prompt assembly sections.
@resultBuilder
public struct PromptAssemblyBuilder {
    /// Includes a single context section.
    public static func buildExpression(_ expression: any ContextSection) -> [any ContextSection] {
        [expression]
    }

    /// Includes an array of context sections.
    public static func buildExpression(_ expression: [any ContextSection]) -> [any ContextSection] {
        expression
    }

    /// Combines multiple components into a single array.
    public static func buildBlock(_ components: [any ContextSection]...) -> [any ContextSection] {
        components.flatMap { $0 }
    }

    /// Handles optional components in the DSL.
    public static func buildOptional(_ component: [any ContextSection]?) -> [any ContextSection] {
        component ?? []
    }

    /// Handles the 'first' case in the DSL.
    public static func buildEither(first component: [any ContextSection]) -> [any ContextSection] {
        component
    }

    /// Handles the 'second' case in the DSL.
    public static func buildEither(second component: [any ContextSection]) -> [any ContextSection] {
        component
    }

    /// Flattens an array of sections in the DSL.
    public static func buildArray(_ components: [[any ContextSection]]) -> [any ContextSection] {
        components.flatMap { $0 }
    }
}

/// A result builder for constructing prompt assembly pipelines from stages.
public typealias PromptAssemblyPipelineBuilder = PipelineBuilder<PromptAssemblyContext, PromptAssemblyEvent>
