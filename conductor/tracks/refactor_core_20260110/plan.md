# Track Plan: MonadCore Refactoring and Context Engine Testing

## Phase 1: Foundation and Mocking
Prepare the testing infrastructure by creating mocks for external dependencies.

- [x] Task: Define protocols for `LLMService` and `PersistenceService` to enable mocking. 2a0ee3d
- [~] Task: Create `TestMocks` in the test bundle for LLM and Database interactions.
- [ ] Task: Conductor - User Manual Verification 'Foundation and Mocking' (Protocol in workflow.md)

## Phase 2: ContextManager Refactoring
Isolate `ContextManager` and apply dependency injection.

- [ ] Task: Refactor `ContextManager` to accept injected service protocols.
- [ ] Task: Write Tests: Create `ContextManagerTests.swift` and implement tests for semantic retrieval.
- [ ] Task: Implement Feature: Ensure `ContextManager` passes all tests using mocks.
- [ ] Task: Conductor - User Manual Verification 'ContextManager Refactoring' (Protocol in workflow.md)

## Phase 3: Comprehensive Testing and Quality
Expand test coverage and finalize the refactoring.

- [ ] Task: Write Tests: Add tests for tag boosting and adaptive learning logic in `ContextManager`.
- [ ] Task: Implement Feature: Refine logic to pass expanded test cases.
- [ ] Task: Verify overall code coverage for `MonadCore` and ensure it meets the >80% target.
- [ ] Task: Conductor - User Manual Verification 'Comprehensive Testing and Quality' (Protocol in workflow.md)
