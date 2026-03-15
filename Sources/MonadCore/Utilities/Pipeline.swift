import ErrorKit
import Foundation
import Logging
import MonadShared

/// Protocol defining a single stage in a pipeline.
public protocol PipelineStage<Context, Event>: Sendable {
    associatedtype Context: Sendable
    associatedtype Event: Sendable

    /// Unique identifier for the stage.
    var id: String { get }

    /// Processes the given context.
    /// - Parameters:
    ///   - context: The context to be processed and potentially modified.
    /// - Returns: A stream of events emitted during processing.
    /// - Throws: An error if processing fails.
    func process(_ context: Context) async throws -> AsyncThrowingStream<Event, Error>
}

public extension PipelineStage {
    /// Default implementation returns the type name.
    var id: String {
        String(describing: Self.self)
    }
}

/// A generic, asynchronous pipeline that executes a series of stages.
public final class Pipeline<Context: Sendable, Event: Sendable>: Sendable {
    private let stages: [any PipelineStage<Context, Event>]
    private let cleanupStages: [any PipelineStage<Context, Event>]
    private let logger: Logger?

    public init(
        stages: [any PipelineStage<Context, Event>] = [],
        cleanupStages: [any PipelineStage<Context, Event>] = [],
        logger: Logger? = nil
    ) {
        self.stages = stages
        self.cleanupStages = cleanupStages
        self.logger = logger
    }

    /// Adds a stage to the pipeline and returns a new pipeline instance.
    /// - Parameter stage: The stage to add.
    /// - Returns: A new pipeline instance with the added stage.
    public func add(_ stage: any PipelineStage<Context, Event>) -> Pipeline<Context, Event> {
        return Pipeline(stages: stages + [stage], cleanupStages: cleanupStages, logger: logger)
    }

    /// Adds a cleanup stage to the pipeline and returns a new pipeline instance.
    /// Cleanup stages are executed even if a primary stage fails.
    /// - Parameter stage: The cleanup stage to add.
    /// - Returns: A new pipeline instance with the added cleanup stage.
    public func cleanup(_ stage: any PipelineStage<Context, Event>) -> Pipeline<Context, Event> {
        return Pipeline(stages: stages, cleanupStages: cleanupStages + [stage], logger: logger)
    }

    /// Sets the logger for the pipeline and returns a new pipeline instance.
    /// - Parameter logger: The logger to use.
    /// - Returns: A new pipeline instance with the logger set.
    public func withLogger(_ logger: Logger) -> Pipeline<Context, Event> {
        return Pipeline(stages: stages, cleanupStages: cleanupStages, logger: logger)
    }

    /// Executes the pipeline on the given context.
    /// - Parameters:
    ///   - context: The context to process.
    /// - Returns: A merged stream of all events from all stages.
    public func execute(_ context: Context) -> AsyncThrowingStream<Event, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let executionError = await runPrimaryStages(context: context, continuation: continuation)
                let finalError = await runCleanupStages(
                    context: context, continuation: continuation, priorError: executionError
                )

                if let error = finalError {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Execution Helpers

    private func runPrimaryStages(
        context: Context,
        continuation: AsyncThrowingStream<Event, Error>.Continuation
    ) async -> Error? {
        for stage in stages {
            if Task.isCancelled { break }
            if let error = await runStage(stage, context: context, continuation: continuation, label: "pipeline") {
                return error
            }
        }
        return nil
    }

    private func runCleanupStages(
        context: Context,
        continuation: AsyncThrowingStream<Event, Error>.Continuation,
        priorError: Error?
    ) async -> Error? {
        var finalError = priorError
        for stage in cleanupStages {
            if let error = await runStage(stage, context: context, continuation: continuation, label: "cleanup") {
                if finalError == nil {
                    finalError = PipelineError.cleanupFailed(id: stage.id, error: error)
                }
            }
        }
        return finalError
    }

    private func runStage(
        _ stage: any PipelineStage<Context, Event>,
        context: Context,
        continuation: AsyncThrowingStream<Event, Error>.Continuation,
        label: String
    ) async -> Error? {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger?.debug("Starting \(label) stage: \(stage.id)")

        do {
            let stream = try await stage.process(context)
            for try await event in stream {
                continuation.yield(event)
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger?.debug("Completed \(label) stage: \(stage.id) in \(String(format: "%.3f", duration))s")
            return nil
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let durationStr = String(format: "%.3f", duration)
            logger?.error("\(label) stage '\(stage.id)' failed after \(durationStr)s: \(error.localizedDescription)")
            return PipelineError.stageFailed(id: stage.id, error: error)
        }
    }
}

/// Errors that can occur during pipeline execution.
public enum PipelineError: Throwable {
    case stageFailed(id: String, error: Error)
    case cleanupFailed(id: String, error: Error)

    public var userFriendlyMessage: String {
        switch self {
        case let .stageFailed(id, error):
            return "Pipeline stage '\(id)' failed: \(ErrorKit.userFriendlyMessage(for: error))"
        case let .cleanupFailed(id, error):
            return "Pipeline cleanup stage '\(id)' failed: \(ErrorKit.userFriendlyMessage(for: error))"
        }
    }
}
