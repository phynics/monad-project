import Foundation

/// A result builder for constructing context gathering pipelines.
@resultBuilder
public struct ContextPipelineBuilder {
    public static func buildBlock(_ components: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]...) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: any PipelineStage<ContextPipelineContext, ContextGatheringEvent>) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        [expression]
    }

    public static func buildOptional(_ component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]?) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component ?? []
    }

    public static func buildEither(first component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component
    }

    public static func buildEither(second component: [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        component
    }

    public static func buildArray(_ components: [[any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]]) -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>] {
        components.flatMap { $0 }
    }
}

/// Convenience typealias for context gathering pipelines.
public typealias ContextPipeline = Pipeline<ContextPipelineContext, ContextGatheringEvent>

public extension ContextPipeline {
    /// Initializes a pipeline using the `@ContextPipelineBuilder` DSL.
    /// - Parameter builder: A closure that returns the stages of the pipeline.
    convenience init(@ContextPipelineBuilder builder: () -> [any PipelineStage<ContextPipelineContext, ContextGatheringEvent>]) {
        self.init(stages: builder())
    }
}
