# Initial Concept
A native AI assistant for macOS and iOS focused on speed, deep context, and local-first privacy through semantic retrieval and document workspace management.

# Product Guide

## Vision
Monad Assistant aims to redefine personal AI interactions by bridging the gap between large language models and local, personal data. It provides a high-performance, private, and deeply contextual environment where users can seamlessly interact with their own information.

## Target Users
- **Power Users and Developers:** Individuals who require fast, reliable LLM access and need to integrate it with their local development workflows and technical knowledge base.
- **Privacy-Conscious Individuals:** Users who prioritize data ownership and want a local-first alternative to traditional cloud-based AI services.
- **Researchers and Students:** Academic and professional users managing extensive document libraries who need sophisticated tools for analysis, summarization, and retrieval.

## Core Goals
- **Native Performance:** Deliver a top-tier macOS and iOS experience using Swift and SwiftUI, optimized for speed and responsiveness.
- **Deep Semantic Retrieval:** Move beyond simple keyword matching with a sophisticated vector-based context engine that learns and adapts to user needs.
- **Local-First Privacy:** Build a robust architecture that prioritizes local processing and persistent storage (via GRDB/SQLite), ensuring user data remains private.
- **Dynamic Document Workspace:** Treat documents as stateful, interactive participants in conversations, allowing for autonomous analysis and precise information retrieval.

## Key Features
- **Adaptive Context Management:** Automatically retrieves relevant memories and notes based on conversation flow and LLM-driven tag boosting.
- **Stateful Document Workspace:** Load, unload, and pin documents to keep the context window focused while maintaining access to critical data.
- **Multi-Model Support:** Integration with providers like OpenAI and local models via Ollama or OpenRouter.
- **Persistent Memory:** Robust storage of conversation history, memories, and notes with semantic search capabilities.
- **Model Context Protocol (MCP):** Implementation of the MCP for extensible tool and data integration.
