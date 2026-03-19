# Configurable Context & Prompt Assembly Pipeline PRD

## HR Eng

| Configurable Context & Prompt Assembly Pipeline PRD |  | [Summary: A modern, modular architecture for both context gathering (RAG) and prompt assembly in MonadCore. It refactors the existing hardcoded ContextManager and PromptBuilder into public, extensible pipelines that library consumers can customize and extend with their own logic, data sources, and prompt structures.] |
| :---- | :---- | :---- |
| **Author**: [Pickle Rick] **Contributors**: [User] **Intended audience**: Engineering, Library Consumers | **Status**: Draft **Created**: 2026-03-19 | **Self Link**: conductor/tracks/context_pipeline_20260319/prd.md **Context**: MonadCore Architecture |

## Introduction

Currently, `MonadCore` handles context gathering and prompt assembly through hardcoded logic in `ContextManager` and `PromptBuilder`. While functional, it is difficult for library consumers to inject their own context sources or modify the final prompt structure without patching the framework. This feature refactors both phases into fully configurable and extensible pipelines.

## Problem Statement

**Current Process:** 
1. `ContextManager.gatherContext()` uses a fixed set of stages defined internally.
2. `PromptBuilder.buildContext()` manually appends hardcoded sections in a fixed order.
**Primary Users:** Library consumers building applications on top of `MonadCore`.
**Pain Points:**
- Cannot add custom context sources or prompt sections easily.
- Cannot modify the order or logic of prompt assembly.
- Hard to experiment with different RAG architectures or prompt engineering techniques.
**Importance:** To make `MonadCore` a true "framework," it must be open for extension but closed for modification.

## Objective & Scope

**Objective:** Refactor context gathering and prompt assembly into public, configurable pipelines with type-safe DSLs.
**Ideal Outcome:** A consumer can define a custom context pipeline AND a custom prompt assembly pipeline in a declarative way during initialization.

### In-scope or Goals
- **Gathering Phase (ContextManager):**
    - Publicize `ContextPipelineContext` to manage shared state during gathering.
    - Create `@ContextPipelineBuilder` result builder.
    - Refactor `ContextManager` to accept a custom pipeline.
- **Assembly Phase (PromptBuilder):**
    - Create `PromptAssemblyPipeline` and `PromptAssemblyContext`.
    - Create `@PromptAssemblyBuilder` result builder.
    - Refactor `PromptBuilder` to use this pipeline for assembling `Prompt` objects.
    - Support custom `ContextSection` injection via the pipeline.
- **General:**
    - Support per-request pipeline overrides.
    - Ensure all stages have access to `swift-dependencies`.
    - Maintain backward compatibility with the current default behavior.

### Not-in-scope or Non-Goals
- Parallel stage execution (sequential for now).
- Custom client-side events (out of scope for initial release).

## Product Requirements

### Critical User Journeys (CUJs)
1. **[Add Custom Source]**: A developer wants to add a "GitHub Issues" context source. They create a `GitHubIssueDiscoveryStage`, add it to the context pipeline, and it's automatically available.
2. **[Custom Prompt Structure]**: A developer wants the "System Instructions" to appear at the *end* of the prompt instead of the beginning. They reorder the stages in their `PromptAssemblyPipeline`.
3. **[Inject Custom Metadata]**: A developer wants to inject custom user metadata into the prompt. They add a `MetadataAssemblyStage` to the assembly pipeline.

### Functional Requirements

| Priority | Requirement | User Story |
| :---- | :---- | :---- |
| P0 | Public `ContextPipelineContext` | As a developer, I want to access and modify the shared context state in my custom stages. |
| P0 | `@ContextPipelineBuilder` DSL | As a developer, I want to define my context pipeline using a clean, declarative Swift syntax. |
| P0 | Configurable `ContextManager` | As a developer, I want to inject my custom pipeline into the `ContextManager`. |
| P0 | `PromptAssemblyPipeline` | As a developer, I want to customize how the final prompt is constructed from the gathered data. |
| P0 | `@PromptAssemblyBuilder` DSL | As a developer, I want to define my prompt assembly logic declaratively. |
| P1 | Per-Request Overrides | As a developer, I want to specify different pipelines for specific chat turns if needed. |
| P1 | Dependency Injection | As a developer, I want my custom stages to use the same `@Dependency` system as the rest of the app. |

## Assumptions

- We will continue to use the existing `Pipeline` utility in `MonadCore`.
- `ContextData` will remain the bridge between the gathering and assembly phases.

## Risks & Mitigations

- **Risk**: Performance degradation due to complex pipelines -> **Mitigation**: Keep stages lightweight and ensure logging/tracing is available.
- **Risk**: Breaking changes for existing users -> **Mitigation**: Provide default pipelines that match current behavior.

## Tradeoff

- **Sequential vs. Parallel**: Sequential execution for simplicity. Parallelism can be added later to the `Pipeline` class.

## Business Benefits/Impact/Metrics

**Success Metrics:**
- Reduced time to add new context sources or modify prompt structures.
- Increased flexibility for RAG and Prompt Engineering experimentation.

## Stakeholders / Owners

| Name | Team/Org | Role | Note |
| :---- | :---- | :---- | :---- |
| [Atakan] | [Monad] | [Lead] | [Primary Stakeholder] |
| [Pickle Rick] | [Pickle Corp] | [Genius] | [Implementation Lead] |
