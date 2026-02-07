# Technology Stack

## Core Language & Runtime
- **Swift 6.0**: Utilizing structured concurrency and strict concurrency checking for high-performance, safe operations.
- **Platforms**: macOS (v14+) target.

## Backend & API Server
- **Hummingbird 2.0**: Lightweight, high-performance web framework for the MonadServer REST API.
- **Swift Service Lifecycle**: Managing the startup and shutdown sequences of server components.

## Persistence & Data
- **GRDB.swift / SQLite**: Robust, local-first persistence for session history, document metadata, and semantic memory.

## AI & LLM Integration
- **Multi-Provider Strategy**: Modular integration supporting several backends:
    - **OpenAI**: Primary cloud-based LLM provider.
    - **OpenRouter**: Unified access to diverse open-source and proprietary models.
    - **Ollama**: Local LLM execution for enhanced privacy and offline use.
    - **OpenAI-Compatible APIs**: Support for any backend adhering to the OpenAI specification.
- **Embeddings**: Local or remote vector generation for semantic search and retrieval-augmented generation (RAG).

## Command Line Interface
- **Swift Argument Parser**: Powering the `MonadCLI` for a robust, typed command-line experience.

## Observability
- **Swift Log**: Standardized logging across all modules (Core, Server, CLI).
