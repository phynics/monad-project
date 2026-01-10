# Track Spec: MonadCore and UI Quality Improvement

## Overview
This track focuses on a comprehensive refactoring and cleanup of the Monad Assistant codebase. The primary goals are to remove vestigial code, improve the modularity of the UI layer, and enhance the efficiency and reliability of context management.

## Functional Requirements

### UI Layer Refactoring (`MonadUI`)
- **ChatViewModel Streamlining:** Extract business logic, tool coordination, and persistence orchestration into dedicated service classes or extensions to reduce the size and complexity of the main view model.
- **State Resilience:** Improve the handling of asynchronous operations to ensure loading and error states are consistently and accurately represented in the UI.
- **Vestigial Code Removal:** Identify and delete unused views, view models, or helper functions that were superseded by newer implementations.

### Context Management Enhancements (`MonadCore`)
- **"Always Append" Optimization:** Refine the logic for notes marked as "Always Append" to prevent context window bloat, potentially through summarization or more selective inclusion based on query relevance.
- **ContextCompressor Efficiency:** Improve the performance and strategy of the `ContextCompressor` when dealing with very large conversation histories.
- **Tool-Calling Loop Optimization:** Refine the interaction between `ChatViewModel` and `ContextManager` during multi-step tool executions to avoid redundant context retrieval calls and reduce latency.

## Non-Functional Requirements
- **Code Quality:** Adhere strictly to the project's Swift 6.0 and concurrency standards.
- **Performance:** Reduce overhead in the main UI thread by moving more orchestration logic to background tasks or actors.
- **Maintainability:** Ensure all public interfaces are well-documented and the separation of concerns between Core and UI is strengthened.

## Acceptance Criteria
- `ChatViewModel` is significantly reduced in complexity and focuses primarily on UI state.
- All loading and error states in the chat interface function correctly and provide clear user feedback.
- Context gathering for complex tool-calling tasks is demonstrably more efficient (fewer redundant calls).
- The project builds successfully with no regressions in existing features.
- All new and refactored code passes existing unit tests.

## Out of Scope
- Major new feature additions.
- Database schema migrations (unless absolutely necessary for cleanup).
