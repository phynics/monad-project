import Foundation

/// A result builder for constructing context gathering pipelines.
@resultBuilder
public struct ContextPipelineBuilder {
    /// Combines multiple stages into a single flat array.
    public static func buildBlock(_ components: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]...) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        components.flatMap { $0 }
    }

    /// Includes a single pipeline stage.
    public static func buildExpression(_ expression: any PipelineStage<ContextPipelineContext, ContextGatheringEvent>) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        [expression]
    }

    /// Handles optional stages in the DSL.
    public static func buildOptional(_ component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]?) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component ?? []
    }

    /// Handles the 'first' case of an 'if-else' or 'switch' in the DSL.
    public static func buildEither(first component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component
    }

    /// Handles the 'second' case of an 'if-else' or 'switch' in the DSL.
    public static func buildEither(second component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component
    }

    /// Flattens an array of stages in the DSL.
    public static func buildArray(_ components: [[any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        components.flatMap { $0 }
    }
}

/// Convenience typealias for context gathering pipelines.
public typealias ContextPipeline = Pipeline<ContextPipelineContext, ContextGatheringEvent>

public extension ContextPipeline {
    /// Initializes a context gathering pipeline using the `@ContextPipelineBuilder` DSL.
    /// - Parameter builder: A closure that returns the stages of the pipeline.
    convenience init(@ContextPipelineBuilder builder: () -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) {
        self.init(stages: builder())
    }
}
