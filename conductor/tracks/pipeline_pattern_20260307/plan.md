# Implementation Plan: Pipeline Pattern

**Phase 1: Pipeline Core Utility**
- [ ] Task: Design the `Pipeline` protocol and `PipelineStage` interface.
- [ ] Task: Create `Sources/MonadCore/Utilities/Pipeline.swift`.
- [ ] Task: Implement `AsyncPipeline` with Fluent API support.
- [ ] Task: Add basic error handling and stage execution logic.
- [ ] Task: **Write Tests**: Create `Tests/MonadCoreTests/Utilities/PipelineTests.swift` with async stage and error cases.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Pipeline Core Utility' (Protocol in workflow.md)

**Phase 2: Advanced Pipeline Features**
- [ ] Task: Implement dynamic stage addition/removal at runtime.
- [ ] Task: Add "Fallback/Cleanup" stage support for error scenarios.
- [ ] Task: Support for `PipelineContext` to manage state across stages.
- [ ] Task: **Write Tests**: Add tests for dynamic stages and context state changes.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Advanced Pipeline Features' (Protocol in workflow.md)

**Phase 3: ChatEngine Refactoring**
- [ ] Task: Define `ChatTurnContext` and corresponding `PipelineStage` protocols.
- [ ] Task: Implement `PromptBuildingStage`, `LLMExecutionStage`, `ToolHandlingStage`, and `PersistenceStage`.
- [ ] Task: Refactor `ChatEngine.processTurn` to utilize the new pipeline.
- [ ] Task: **Write Tests**: Verify `ChatEngine` behavior remains identical through regression tests in `MonadCoreTests`.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: ChatEngine Refactoring' (Protocol in workflow.md)

**Phase 4: ContextManager Refactoring**
- [ ] Task: Refactor the context gathering logic into a modular pipeline.
- [ ] Task: **Write Tests**: Ensure context gathering remains functional and accurate.
- [ ] Task: Conductor - User Manual Verification 'Phase 4: ContextManager Refactoring' (Protocol in workflow.md)
