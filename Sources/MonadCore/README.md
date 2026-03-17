# MonadCore

MonadCore is the core orchestration library for the Monad platform. It provides the infrastructure for autonomous agent execution, chat turn management, and tool routing.

## Documentation

- [Architecture Overview](docs/Architecture.md) - Deep dive into the engine's design, pipeline stages, and ReAct loop.
- [Setup & Configuration](docs/Setup.md) - How to configure LLM providers, database storage, and dependency injection.
- [Usage & Examples](docs/Usage.md) - Step-by-step guide to initializing agents and running chat streams.

## Key Components

### MonadCoreChat
The interface boundary for MonadCore. Accepts all required services as init parameters and internally orchestrates the chat lifecycle — context gathering, LLM interaction, tool execution, and state persistence.

### AgentInstance
Represents a live, persistent agent entity. Each instance has its own private workspace (long-term memory) and private timeline (internal monologue).

### AgentInstanceManager
Handles the lifecycle of `AgentInstance` entities, including creation from templates, attachment to timelines, and workspace management.

## Getting Started

To get started with MonadCore, refer to the [Usage Guide](docs/Usage.md).

```swift
import MonadCore
import MonadShared

let chat = MonadCoreChat(
    llmService: myLLM,
    messageStore: myMessageStore,
    timelineManager: myTimelineManager,
    toolRouter: myToolRouter,
    agentInstanceStore: myAgentInstanceStore,
    clientStore: myClientStore,
    timelinePersistence: myTimelinePersistence,
    workspacePersistence: myWorkspacePersistence,
    memoryStore: myMemoryStore,
    toolPersistence: myToolPersistence,
    agentTemplateStore: myAgentTemplateStore,
    embeddingService: myEmbeddingService
)

let stream = try await chat.run(
    timelineId: timelineId,
    message: "Hello!"
)

for try await event in stream {
    // Process chat events
}
```
