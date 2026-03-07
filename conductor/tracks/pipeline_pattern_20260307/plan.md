# Implementation Plan: Pipeline Pattern

**Phase 1: Pipeline Core Utility**
- [x] Task: Design the `Pipeline` protocol and `PipelineStage` interface. (a616496)
- [x] Task: Create `Sources/MonadCore/Utilities/Pipeline.swift`. (a616496)
- [x] Task: Implement `AsyncPipeline` with Fluent API support. (a616496)
- [x] Task: Add basic error handling and stage execution logic. (a616496)
- [x] Task: **Write Tests**: Create `Tests/MonadCoreTests/Utilities/PipelineTests.swift` with async stage and error cases. (a616496)
- [x] Task: Conductor - User Manual Verification 'Phase 1: Pipeline Core Utility' (Protocol in workflow.md) (a616496)

**Phase 2: Advanced Pipeline Features**
- [x] Task: Implement dynamic stage addition/removal at runtime. (a616496)
- [x] Task: Add "Fallback/Cleanup" stage support for error scenarios. (a616496)
- [x] Task: Support for `PipelineContext` to manage state across stages. (a616496)
- [x] Task: **Write Tests**: Add tests for dynamic stages and context state changes. (a616496)
- [x] Task: Conductor - User Manual Verification 'Phase 2: Advanced Pipeline Features' (Protocol in workflow.md) (a616496)

**Phase 3: ChatEngine Refactoring**
- [x] Task: Define `ChatTurnContext` and corresponding `PipelineStage` protocols. (a616496)
- [x] Task: Implement `PromptBuildingStage`, `LLMExecutionStage`, `ToolHandlingStage`, and `PersistenceStage`. (a616496)
- [x] Task: Refactor `ChatEngine.processTurn` to utilize the new pipeline. (a616496)
- [x] Task: **Write Tests**: Verify `ChatEngine` behavior remains identical through regression tests in `MonadCoreTests`. (a616496)
- [x] Task: Conductor - User Manual Verification 'Phase 3: ChatEngine Refactoring' (Protocol in workflow.md) (a616496)

**Phase 4: ContextManager Refactoring**
- [x] Task: Refactor the context gathering logic into a modular pipeline. (a616496)
- [x] Task: **Write Tests**: Ensure context gathering remains functional and accurate. (a616496)
- [x] Task: Conductor - User Manual Verification 'Phase 4: ContextManager Refactoring' (Protocol in workflow.md) (a616496)
