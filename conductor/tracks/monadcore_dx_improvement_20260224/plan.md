# Implementation Plan: MonadCore Developer Experience (DX) Improvement

## Phase 1: Persistence Layer Refactoring (Hard Cutover) [checkpoint: 1e6f5af]
- [x] Task: Define domain-specific storage protocols c297743
    - [x] Write unit tests for domain-specific store interfaces and mocking
    - [x] Implement `MemoryStoreProtocol`, `MessageStoreProtocol`, `SessionPersistenceProtocol`, `JobStoreProtocol`, `AgentStoreProtocol`, `WorkspacePersistenceProtocol`, and `ClientStoreProtocol`
- [x] Task: Migrate service consumers to narrow protocols 1e6f5af
    - [x] Update `ContextManager` tests and implementation to use narrow protocols
    - [x] Update `SessionManager` tests and implementation to use narrow protocols
    - [x] Update `WorkspaceStore` and `SessionStore` tests and implementation
- [x] Task: Refactor testing mocks and finalize cutover 1e6f5af
    - [x] Split `MockPersistenceService` into focused domain mocks
    - [x] Remove `PersistenceServiceProtocol` and update all remaining references in `MonadServer` and `MonadCLI`
- [x] Task: Conductor - User Manual Verification 'Phase 1: Persistence Layer Refactoring' (Protocol in workflow.md)

## Phase 2: Type-Safe Tool Parameter System [checkpoint: 1e6f5af]
- [x] Task: Implement `ToolParameterSchema` builder
    - [x] Write unit tests for the schema DSL (ObjectBuilder)
    - [x] Implement `ToolParameterSchema` and `ObjectBuilder` logic
- [x] Task: Implement `ToolParameters` extraction wrapper
    - [x] Write unit tests for safe parameter extraction and `ToolError.invalidArgument` cases
    - [x] Implement `ToolParameters` with `require` and `optional` methods
- [x] Task: Migrate existing tools to the new system
    - [x] Migrate `ReadFileTool` tests and implementation as a reference
    - [x] Incrementally migrate all other tools in `MonadCore/Models/Tools/`
- [x] Task: Conductor - User Manual Verification 'Phase 2: Type-Safe Tool Parameter System' (Protocol in workflow.md)

## Phase 3: Dependency Safety & Validation [checkpoint: 1e6f5af]
- [x] Task: Enhance `DependencyKey` actionable error messages
    - [x] Write tests verifying that unconfigured dependencies trigger descriptive error messages
    - [x] Update all `DependencyKey` defaults in `OrchestrationDependencies.swift`, `StorageDependencies.swift`, and `LLMDependencies.swift`
- [x] Task: Implement `DependencyValidator`
    - [x] Write unit tests for dependency configuration validation
    - [x] Implement `DependencyValidator.validateRequired()` utility
- [x] Task: Conductor - User Manual Verification 'Phase 3: Dependency Safety & Validation' (Protocol in workflow.md)

## Phase 4: Testing Infrastructure & Swift Testing Migration [checkpoint: Current]
- [x] Task: Implement Test Fixtures and Builders 93819
    - [x] Write tests for the builders themselves
    - [x] Implement `TestFixtures` with sensible defaults for all core models
- [x] Task: Implement Test Helpers for Streams and Dependencies 94109
    - [x] Write unit tests for `collect()` and `withMockDependencies()`
    - [x] Implement stream collection and mock dependency injection helpers
- [x] Task: Migrate MonadCore to Swift Testing 94413
    - [x] Convert all XCTest files in `MonadCore` to `@Test` framework
    - [x] Remove XCTest boilerplate and adopt new helpers across the suite
- [x] Task: Conductor - User Manual Verification 'Phase 4: Testing Infrastructure & Swift Testing Migration' (Protocol in workflow.md)

## Phase 5: Documentation [checkpoint: Current]
- [x] Task: Create module-level DocC documentation
    - [x] Implement `MonadCore.docc` with architecture overview and guides
- [x] Task: Complete API DocC coverage
    - [x] Add documentation comments to all public types and protocols
    - [x] Document complex logic blocks in `ChatEngine` and `ContextManager`
- [x] Task: Conductor - User Manual Verification 'Phase 5: Documentation' (Protocol in workflow.md)

## Phase 6: Error Handling Improvements [checkpoint: Current]
- [x] Task: Surface tool execution errors 94907
    - [x] Write tests verifying tool errors are emitted in the `ChatEvent` stream
    - [x] Update `ChatEngine` event emission for tool failures
- [x] Task: Implement remediation hints and configuration validation 95247
    - [x] Write unit tests for `ToolError.remediation` and `Configuration.validate()`
    - [x] Implement remediation hints and the new `ConfigurationError` enum
- [x] Task: Conductor - User Manual Verification 'Phase 6: Error Handling Improvements' (Protocol in workflow.md)