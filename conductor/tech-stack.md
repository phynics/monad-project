# Technology Stack

## Core Language & Platform
- **Swift 6.0**: Utilizing the latest concurrency features and performance improvements.
- **macOS v15**: Targeted for the latest Apple silicon and system features.

## Backend & API
- **Hummingbird 2.0**: A lightweight, high-performance Swift web framework.
- **Hummingbird WebSocket**: For real-time streaming chat support.
- **Swift Service Lifecycle**: To manage application startup and shutdown gracefully.

## Persistence & Search
- **GRDB.swift**: A toolkit for SQLite databases with focus on safety and performance.
- **USearch**: A high-performance vector search engine for semantic memory.

## AI & Prompting
- **OpenAI Swift (MacPaw)**: Integration with OpenAI's models.
- **MonadPrompt**: A custom internal DSL for context-aware prompt construction.

## Architecture & Infrastructure
- **Modular Architecture**: Separated into Core, Server, CLI, Client, Prompt, and Shared modules.
- **Swift Dependencies**: For robust dependency injection and testing.
- **Swift Argument Parser**: For a powerful and typed CLI experience.
- **Swift Log**: Standard logging for server and core logic.

## Build & Development Tools
- **Swift Package Manager (SPM)**: Primary build system and dependency manager.
- **XcodeGen**: For generating Xcode projects from a specification.
- **Makefile**: For standardizing development workflows (build, test, run).
