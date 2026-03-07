import Foundation
import Logging
import MonadShared

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

public extension PipelineStage {
    /// Default implementation returns the type name.
    var id: String {
        String(describing: Self.self)
    }
}

/// A generic, asynchronous pipeline that executes a series of stages.
public final class Pipeline<Context>: Sendable {
    private let stages: [any PipelineStage<Context>]
    private let cleanupStages: [any PipelineStage<Context>]
    private let logger: Logger?
    
    public init(
        stages: [any PipelineStage<Context>] = [],
        cleanupStages: [any PipelineStage<Context>] = [],
        logger: Logger? = nil
    ) {
        self.stages = stages
        self.cleanupStages = cleanupStages
        self.logger = logger
    }
    
    /// Adds a stage to the pipeline and returns a new pipeline instance.
    /// - Parameter stage: The stage to add.
    /// - Returns: A new pipeline instance with the added stage.
    public func add(_ stage: any PipelineStage<Context>) -> Pipeline<Context> {
        return Pipeline(stages: self.stages + [stage], cleanupStages: self.cleanupStages, logger: self.logger)
    }

    /// Adds a cleanup stage to the pipeline and returns a new pipeline instance.
    /// Cleanup stages are executed even if a primary stage fails.
    /// - Parameter stage: The cleanup stage to add.
    /// - Returns: A new pipeline instance with the added cleanup stage.
    public func cleanup(_ stage: any PipelineStage<Context>) -> Pipeline<Context> {
        return Pipeline(stages: self.stages, cleanupStages: self.cleanupStages + [stage], logger: self.logger)
    }
    
    /// Sets the logger for the pipeline and returns a new pipeline instance.
    /// - Parameter logger: The logger to use.
    /// - Returns: A new pipeline instance with the logger set.
    public func withLogger(_ logger: Logger) -> Pipeline<Context> {
        return Pipeline(stages: self.stages, cleanupStages: self.cleanupStages, logger: logger)
    }

    /// Executes the pipeline on the given context.
    /// - Parameter context: The context to process.
    /// - Throws: A `PipelineError` if any stage fails.
    public func execute(_ context: inout Context) async throws {
        var executionError: Error?
        
        for stage in stages {
            let startTime = CFAbsoluteTimeGetCurrent()
            logger?.debug("Starting pipeline stage: \(stage.id)")
            
            do {
                try await stage.process(&context)
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                logger?.debug("Completed pipeline stage: \(stage.id) in \(String(format: "%.3f", duration))s")
            } catch {
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                logger?.error("Pipeline stage '\(stage.id)' failed after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
                executionError = PipelineError.stageFailed(id: stage.id, error: error)
                break
            }
        }
        
        // Execute cleanup stages regardless of success/failure
        for stage in cleanupStages {
            let startTime = CFAbsoluteTimeGetCurrent()
            logger?.debug("Starting pipeline cleanup stage: \(stage.id)")
            
            do {
                try await stage.process(&context)
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                logger?.debug("Completed pipeline cleanup stage: \(stage.id) in \(String(format: "%.3f", duration))s")
            } catch {
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                logger?.error("Pipeline cleanup stage '\(stage.id)' failed after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
                // If we already have an error, we log this one but prioritize the first error.
                // If no error yet, this becomes the primary error.
                if executionError == nil {
                    executionError = PipelineError.cleanupFailed(id: stage.id, error: error)
                }
            }
        }
        
        if let error = executionError {
            throw error
        }
    }
}

/// Errors that can occur during pipeline execution.
public enum PipelineError: LocalizedError {
    case stageFailed(id: String, error: Error)
    case cleanupFailed(id: String, error: Error)
    
    public var errorDescription: String? {
        switch self {
        case .stageFailed(let id, let error):
            return "Pipeline stage '\(id)' failed: \(error.localizedDescription)"
        case .cleanupFailed(let id, let error):
            return "Pipeline cleanup stage '\(id)' failed: \(error.localizedDescription)"
        }
    }
}
