import Foundation

/// Protocol defining a single stage in a pipeline.
public protocol PipelineStage<Context>: Sendable {
    associatedtype Context
    
    /// Unique identifier for the stage.
    var id: String { get }
    
    /// Processes the given context.
    /// - Parameter context: The context to be processed and potentially modified.
    /// - Throws: An error if processing fails.
    func process(_ context: inout Context) async throws
}

/// A generic, asynchronous pipeline that executes a series of stages.
public final class Pipeline<Context>: Sendable {
    private let stages: [any PipelineStage<Context>]
    
    public init(stages: [any PipelineStage<Context>] = []) {
        self.stages = stages
    }
    
    /// Adds a stage to the pipeline and returns a new pipeline instance.
    /// - Parameter stage: The stage to add.
    /// - Returns: A new pipeline instance with the added stage.
    public func add(_ stage: any PipelineStage<Context>) -> Pipeline<Context> {
        return Pipeline(stages: self.stages + [stage])
    }
    
    /// Executes the pipeline on the given context.
    /// - Parameter context: The context to process.
    /// - Throws: A `PipelineError` if any stage fails.
    public func execute(_ context: inout Context) async throws {
        for stage in stages {
            do {
                try await stage.process(&context)
            } catch {
                throw PipelineError.stageFailed(id: stage.id, error: error)
            }
        }
    }
}

/// Errors that can occur during pipeline execution.
public enum PipelineError: LocalizedError {
    case stageFailed(id: String, error: Error)
    
    public var errorDescription: String? {
        switch self {
        case .stageFailed(let id, let error):
            return "Pipeline stage '\(id)' failed: \(error.localizedDescription)"
        }
    }
}
