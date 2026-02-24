# Implementation Plan: MonadCore Developer Experience (DX) Improvement

## Phase 1: Persistence Layer Refactoring (Hard Cutover)
- [~] Task: Define domain-specific storage protocols
    - [ ] Write unit tests for domain-specific store interfaces and mocking
    - [ ] Implement `MemoryStoreProtocol`, `MessageStoreProtocol`, `SessionPersistenceProtocol`, `JobStoreProtocol`, `AgentStoreProtocol`, `WorkspacePersistenceProtocol`, and `ClientStoreProtocol`
- [ ] Task: Migrate service consumers to narrow protocols
    - [ ] Update `ContextManager` tests and implementation to use narrow protocols
    - [ ] Update `SessionManager` tests and implementation to use narrow protocols
    - [ ] Update `WorkspaceStore` and `SessionStore` tests and implementation
- [ ] Task: Refactor testing mocks and finalize cutover
    - [ ] Split `MockPersistenceService` into focused domain mocks
    - [ ] Remove `PersistenceServiceProtocol` and update all remaining references in `MonadServer` and `MonadCLI`
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Persistence Layer Refactoring' (Protocol in workflow.md)

## Phase 2: Type-Safe Tool Parameter System
- [ ] Task: Implement `ToolParameterSchema` builder
    - [ ] Write unit tests for the schema DSL (ObjectBuilder)
    - [ ] Implement `ToolParameterSchema` and `ObjectBuilder` logic
- [ ] Task: Implement `ToolParameters` extraction wrapper
    - [ ] Write unit tests for safe parameter extraction and `ToolError.invalidArgument` cases
    - [ ] Implement `ToolParameters` with `require` and `optional` methods
- [ ] Task: Migrate existing tools to the new system
    - [ ] Migrate `ReadFileTool` tests and implementation as a reference
    - [ ] Incrementally migrate all other tools in `MonadCore/Models/Tools/`
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Type-Safe Tool Parameter System' (Protocol in workflow.md)

## Phase 3: Dependency Safety & Validation
- [ ] Task: Enhance `DependencyKey` actionable error messages
    - [ ] Write tests verifying that unconfigured dependencies trigger descriptive error messages
    - [ ] Update all `DependencyKey` defaults in `OrchestrationDependencies.swift`, `StorageDependencies.swift`, and `LLMDependencies.swift`
- [ ] Task: Implement `DependencyValidator`
    - [ ] Write unit tests for dependency configuration validation
    - [ ] Implement `DependencyValidator.validateRequired()` utility
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Dependency Safety & Validation' (Protocol in workflow.md)

## Phase 4: Testing Infrastructure & Swift Testing Migration
- [ ] Task: Implement Test Fixtures and Builders
    - [ ] Write tests for the builders themselves
    - [ ] Implement `TestFixtures` with sensible defaults for all core models
- [ ] Task: Implement Test Helpers for Streams and Dependencies
    - [ ] Write unit tests for `collect()` and `withMockDependencies()`
    - [ ] Implement stream collection and mock dependency injection helpers
- [ ] Task: Migrate MonadCore to Swift Testing
    - [ ] Convert all XCTest files in `MonadCore` to `@Test` framework
    - [ ] Remove XCTest boilerplate and adopt new helpers across the suite
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Testing Infrastructure & Swift Testing Migration' (Protocol in workflow.md)

## Phase 5: Documentation
- [ ] Task: Create module-level DocC documentation
    - [ ] Implement `MonadCore.docc` with architecture overview and guides
- [ ] Task: Complete API DocC coverage
    - [ ] Add documentation comments to all public types and protocols
    - [ ] Document complex logic blocks in `ChatEngine` and `ContextManager`
- [ ] Task: Conductor - User Manual Verification 'Phase 5: Documentation' (Protocol in workflow.md)

## Phase 6: Error Handling Improvements
- [ ] Task: Surface tool execution errors
    - [ ] Write tests verifying tool errors are emitted in the `ChatEvent` stream
    - [ ] Update `ChatEngine` event emission for tool failures
- [ ] Task: Implement remediation hints and configuration validation
    - [ ] Write unit tests for `ToolError.remediation` and `Configuration.validate()`
    - [ ] Implement remediation hints and the new `ConfigurationError` enum
- [ ] Task: Conductor - User Manual Verification 'Phase 6: Error Handling Improvements' (Protocol in workflow.md)
