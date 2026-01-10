# Track Plan: MonadCore and UI Quality Improvement

## Phase 1: Context Management Refinement
Optimize context handling logic in MonadCore.

- [ ] Task: Write Tests: Enhance `ContextManagerTests` to cover "Always Append" clutter scenarios.
- [ ] Task: Implement Feature: Update `ContextManager` to filter or summarize "Always Append" notes based on query relevance.
- [ ] Task: Write Tests: Add stress tests for `ContextCompressor` with very long histories.
- [ ] Task: Implement Feature: Optimize `ContextCompressor` chunking and summarization strategies.
- [ ] Task: Conductor - User Manual Verification 'Context Management Refinement' (Protocol in workflow.md)

## Phase 2: UI Layer Modularization
Refactor `ChatViewModel` and extract non-UI concerns.

- [ ] Task: Write Tests: Create `ChatViewModel` unit tests for state transitions (loading, error, success).
- [ ] Task: Implement Feature: Refactor `ChatViewModel` by extracting tool coordination into a `ToolOrchestrator` service.
- [ ] Task: Implement Feature: Extract persistence orchestration from `ChatViewModel` into dedicated methods or extensions.
- [ ] Task: Implement Feature: Remove identified vestigial code (unused views and helpers).
- [ ] Task: Conductor - User Manual Verification 'UI Layer Modularization' (Protocol in workflow.md)

## Phase 3: Final Integration and Quality Assurance
Ensure overall system stability and performance.

- [ ] Task: Write Tests: Implement integration tests for the multi-step tool-calling loop.
- [ ] Task: Implement Feature: Refine the tool-calling loop to eliminate redundant context retrieval calls.
- [ ] Task: Verify overall code coverage for refactored modules and ensure it meets the >80% target.
- [ ] Task: Conductor - User Manual Verification 'Final Integration and QA' (Protocol in workflow.md)
