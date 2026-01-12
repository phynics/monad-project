# Track Plan: MonadCore and UI Quality Improvement

## Phase 1: Context Management Refinement [checkpoint: 9ca76a9]
Optimize context handling logic in MonadCore.

- [x] Task: Write Tests: Enhance `ContextManagerTests` to cover "Always Append" clutter scenarios. 6f0ddbf
- [x] Task: Implement Feature: Update `ContextManager` to filter or summarize "Always Append" notes based on query relevance. 6f0ddbf
- [x] Task: Write Tests: Add stress tests for `ContextCompressor` with very long histories. 6f0ddbf
- [x] Task: Implement Feature: Optimize `ContextCompressor` chunking and summarization strategies. 6f0ddbf
- [x] Task: Conductor - User Manual Verification 'Context Management Refinement' (Protocol in workflow.md) [checkpoint: 9ca76a9]

## Phase 2: UI Layer Modularization [checkpoint: d0fc98e]
Refactor `ChatViewModel` and extract non-UI concerns.

- [x] Task: Write Tests: Create `ChatViewModel` unit tests for state transitions (loading, error, success). 146fd73
- [x] Task: Implement Feature: Refactor `ChatViewModel` by extracting tool coordination into a `ToolOrchestrator` service. 146fd73
- [x] Task: Implement Feature: Extract persistence orchestration from `ChatViewModel` into dedicated methods or extensions. 146fd73
- [x] Task: Implement Feature: Remove identified vestigial code (unused views and helpers). 146fd73
- [x] Task: Conductor - User Manual Verification 'UI Layer Modularization' (Protocol in workflow.md) [checkpoint: d0fc98e]

## Phase 3: Final Integration and Quality Assurance [checkpoint: e157c70]
Ensure overall system stability and performance.

- [x] Task: Write Tests: Implement integration tests for the multi-step tool-calling loop. 2fa046d
- [x] Task: Implement Feature: Refine the tool-calling loop to eliminate redundant context retrieval calls. 2fa046d
- [x] Task: Verify overall code coverage for refactored modules and ensure it meets the >80% target. 2fa046d
- [x] Task: Conductor - User Manual Verification 'Final Integration and QA' (Protocol in workflow.md) [checkpoint: e157c70]
