# Specification: MonadCore Developer Experience (DX) Improvement Plan

## Overview
This track implements a comprehensive series of improvements to the `MonadCore` logic library to reduce development friction, improve type safety, and modernize the testing and documentation infrastructure. The goal is to transform `MonadCore` into a robust, developer-friendly framework that provides compile-time guidance and clear error surfaces.

## Functional Requirements

### 1. Persistence Layer Refactoring (Hard Cutover)
- **Domain Protocol Split:** Split the "God protocol" `PersistenceServiceProtocol` into 7 focused domain protocols: `MemoryStoreProtocol`, `MessageStoreProtocol`, `SessionPersistenceProtocol`, `JobStoreProtocol`, `AgentStoreProtocol`, `WorkspacePersistenceProtocol`, and `ClientStoreProtocol`.
- **Consumer Migration:** Update all consumers (e.g., `ContextManager`, `SessionManager`, `WorkspaceStore`) to depend strictly on the narrowest domain protocols they require.
- **Mock Refactoring:** Split `MockPersistenceService` into individual, focused mocks for each domain protocol.
- **Protocol Removal:** Completely remove the monolithic `PersistenceServiceProtocol` to ensure no new code reverts to the "God protocol" pattern.

### 2. Type-Safe Tool Parameter System
- **Schema Builder:** Implement `ToolParameterSchema` using a Result Builder or DSL to replace raw `[String: Any]` JSON Schema dictionaries.
- **Parameter Extraction:** Implement a `ToolParameters` wrapper for type-safe, throwing extraction of arguments (e.g., `params.require("path", as: String.self)`).
- **Tool Migration:** Migrate all existing tools (e.g., `ReadFileTool`) to use the new schema builder and extraction logic.

### 3. Dependency Safety & Validation
- **Actionable Errors:** Replace generic `fatalError` calls in `DependencyKey` defaults with detailed messages explaining *how* to configure the missing dependency.
- **Dependency Validator:** Create a `DependencyValidator` utility to check for required configurations at application startup.

### 4. Testing Infrastructure Modernization
- **Swift Testing Migration:** Migrate all `MonadCore` tests from XCTest to the Swift Testing framework (`@Test`).
- **Test Data Builders:** Implement `TestFixtures` with sensible defaults for `Memory`, `Session`, `Message`, and `Job` models.
- **Test Helpers:** Add `withMockDependencies` and `collect(_ stream:)` helpers to reduce per-test boilerplate.

### 5. Documentation & Error Surface
- **DocC Integration:** Create a module-level DocC landing page with an architecture overview and quick-start guides.
- **API Documentation:** Complete DocC coverage for all public types, protocols, and complex logic blocks.
- **Error Remediation:** Add `remediation` hints to `ToolError` and surface tool-level execution errors through the `ChatEvent` stream.

## Non-Functional Requirements
- **Performance:** Ensure the protocol split and composition do not introduce measurable overhead in dependency resolution.
- **Type Safety:** Maximize compile-time checks for tool parameters and dependency injection.
- **Maintainability:** Reduce the size and complexity of mock implementations.

## Acceptance Criteria
- [ ] `PersistenceServiceProtocol` is removed and all 7 domain protocols are implemented.
- [ ] All `MonadCore` consumers compile using narrow domain dependencies.
- [ ] All `Tool` implementations use `ToolParameterSchema` and `ToolParameters`.
- [ ] `MonadCore` tests achieve 100% migration to Swift Testing.
- [ ] Module-level DocC documentation is generated and accurate.
- [ ] `swift test` passes for the entire project.

## Out of Scope
- Refactoring `MonadServer` or `MonadCLI` internal logic (only dependency updates required by the core refactor).
- Replacing `GRDB` or `USearch` implementations.
