# Track Plan: MonadCore Refactoring and Context Engine Testing

## Phase 1: Foundation and Mocking [checkpoint: df5218c]
Prepare the testing infrastructure by creating mocks for external dependencies.

- [x] Task: Define protocols for `LLMService` and `PersistenceService` to enable mocking. 2a0ee3d
- [x] Task: Create `TestMocks` in the test bundle for LLM and Database interactions. 2a0ee3d
- [x] Task: Conductor - User Manual Verification 'Foundation and Mocking' (Protocol in workflow.md) [checkpoint: df5218c]

## Phase 2: ContextManager Refactoring [checkpoint: 2dee3fd]
Isolate `ContextManager` and apply dependency injection.

- [x] Task: Refactor `ContextManager` to accept injected service protocols. 2a0ee3d
- [x] Task: Write Tests: Create `ContextManagerTests.swift` and implement tests for semantic retrieval. 8694f06
- [x] Task: Implement Feature: Ensure `ContextManager` passes all tests using mocks. 8694f06
- [x] Task: Conductor - User Manual Verification 'ContextManager Refactoring' (Protocol in workflow.md) [checkpoint: 2dee3fd]
- [ ] Task: Conductor - User Manual Verification 'ContextManager Refactoring' (Protocol in workflow.md)

## Phase 3: Comprehensive Testing and Quality
Expand test coverage and finalize the refactoring.

- [x] Task: Write Tests: Add tests for tag boosting and adaptive learning logic in `ContextManager`. ce61ec3
- [x] Task: Implement Feature: Refine logic to pass expanded test cases. ce61ec3
- [~] Task: Verify overall code coverage for `MonadCore` and ensure it meets the >80% target.
- [ ] Task: Conductor - User Manual Verification 'Comprehensive Testing and Quality' (Protocol in workflow.md)
