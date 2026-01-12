# Initial Concept
A native AI assistant for macOS and iOS, now featuring a distributed architecture with high-performance gRPC communication, focused on speed, deep context, and local-first privacy through semantic retrieval and document workspace management.

# Product Guide

## Vision
Monad Assistant aims to redefine personal AI interactions by bridging the gap between large language models and local, personal data. It provides a high-performance, private, and deeply contextual environment where users can seamlessly interact with their own information.

## Target Users
- **Power Users and Developers:** Individuals who require fast, reliable LLM access and need to integrate it with their local development workflows and technical knowledge base.
- **Privacy-Conscious Individuals:** Users who prioritize data ownership and want a local-first alternative to traditional cloud-based AI services.

## Core Goals
- **Deep Semantic Retrieval:** Move beyond simple keyword matching with a sophisticated vector-based context engine and direct SQL-driven data interaction.
- **Local-First Privacy:** Build a robust architecture that prioritizes local processing and persistent storage (via GRDB/SQLite), ensuring user data remains private.
- **Native Performance:** Deliver a top-tier macOS and iOS experience using Swift and SwiftUI, optimized for speed and responsiveness.
- **Distributed Architecture:** Decouples core logic from the UI, allowing the assistant to run on a central server (Docker/Linux) while serving multiple native clients.
- **Multi-Interface Access:** Enables interaction through secondary channels like Signal, providing flexibility in how users engage with their assistant.

## Key Features
- **Adaptive Context Management:** Automatically retrieves relevant memories and globally injects notes, leveraging direct SQL-driven persistence.
- **RAW SQL Execution:** Provides the agent with wide latitude to manage custom tables and state while ensuring core data remains immutable.
- **Stateful Document Workspace:** Load, unload, and pin documents to keep the context window focused while maintaining access to critical data.
- **Multi-Model Support:** Integration with providers like OpenAI and local models via Ollama or OpenRouter.
- **Persistent Memory:** Robust storage of conversation history, memories, and notes with semantic search capabilities.
- **Remote Server Mode:** Support for gRPC-based communication with a remote MonadServer, enabling shared state across different client types.
