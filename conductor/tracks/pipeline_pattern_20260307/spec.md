# Specification: Pipeline Pattern Implementation

**Overview**
Introduce a generic, high-performance Pipeline pattern utility to the `MonadCore` framework. This will decouple complex sequential processes—starting with `ChatEngine.processTurn` and `ContextManager`—into discrete, testable, and reusable stages.

**Functional Requirements**
1.  **Generic Pipeline Utility**:
    -   Implement a `Pipeline<Context>` class/struct in `MonadCore`.
    -   Provide a **Fluent API** for adding stages (e.g., `pipeline.add(Stage1()).add(Stage2())`).
    -   Support **Full Async/Await** for all stages, including cancellation support.
2.  **Dynamic Stage Management**:
    -   Stages should be protocols (`PipelineStage`) allowing for diverse implementations.
    -   Support adding/removing stages at runtime or via configuration.
3.  **Error Handling & Recovery**:
    -   Built-in mechanism for error propagation or recovery within the pipeline.
    -   Optional "fallback" or "cleanup" stages.
4.  **Reference Implementations (Refactoring)**:
    -   **ChatEngine Refactor**: Decompose `processTurn` into stages: `PromptBuildingStage`, `LLMExecutionStage`, `ToolHandlingStage`, `PersistenceStage`.
    -   **Context Pipeline**: Refactor the context gathering flow in `ContextManager` into a pipeline.

**Acceptance Criteria**
1.  A reusable `Pipeline` utility exists in `MonadCore/Utilities/Pipeline`.
2.  `ChatEngine.processTurn` is fully refactored to use the new Pipeline, passing all existing tests.
3.  New unit tests verify the Pipeline's ability to handle async stages, errors, and cancellation.
4.  Documentation includes examples of how to create and execute a custom pipeline.

**Out of Scope**
-   Applying the pipeline to other services not mentioned (e.g., TimelineManager).
-   Advanced middleware/interceptor support (can be added later).
