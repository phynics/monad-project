# MonadCore: General-Purpose Agent Framework Guide

MonadCore is a modular, high-performance Swift framework for building and orchestrating autonomous AI agents. It provides a structured environment for agents to execute tasks, use tools, and coordinate with each other.

---

## 1. Core Concepts

### Agents
An **Agent** is an autonomous entity that can perceive its environment (history, RAG context) and take actions (tool calls).
- **`AgentProtocol`**: The fundamental interface for all agents.
- **`AgentManifest`**: Structured metadata (ID, name, capabilities) for discovery.
- **`BaseAgent`**: A convenient base class that handles the ReAct loop and common boilerplate.

### Jobs (Tasks)
Execution is managed via **Jobs**.
- **Persistent**: Jobs are stored in the database and survive restarts.
- **Hierarchical**: Jobs can have a `parentId`, forming a task tree.
- **Status Tracking**: Pending, In-Progress, Completed, Failed, Cancelled.

### Orchestration
- **`MonadEngine`**: The central entry point that ties together persistence, LLM services, and registries.
- **`ReasoningEngine`**: Implements the core multi-turn loop (ReAct) used by agents.
- **`JobRunnerService`**: A background service that monitors the database and executes pending jobs.

---

## 2. Defining an Agent

To create a new agent, inherit from `BaseAgent`.

```swift
import MonadCore
import Foundation

public class ResearchAgent: BaseAgent {
    public init() {
        let manifest = AgentManifest(
            id: "researcher",
            name: "Research Agent",
            description: "Specializes in searching and summarizing information.",
            capabilities: ["search", "summarization"]
        )
        super.init(manifest: manifest)
    }

    // Override the system instructions to define behavior
    open override var systemInstructions: String {
        """
        You are a Researcher. Your goal is to provide deep insights on any topic.
        Use the search tools extensively.
        """
    }
}
```

---

## 3. Dependency Injection

MonadCore uses `swift-dependencies`. This allows agents to access core services without manual passing.

### Accessing Services in Agents
Inside a `BaseAgent` subclass, you have access to:
- `llmService`
- `persistenceService`
- `reasoningEngine`

### Registering Dependencies
In your application entry point (e.g., `MonadServerApp`), inject the engine:

```swift
try await withDependencies {
    $0.withEngine(engine)
} operation: {
    // Run your app here
}
```

---

## 4. Inter-Agent Communication

Agents can delegate work to others using the `LaunchSubagentTool`.

### The Coordinator Pattern
The `AgentCoordinator` is a specialized agent designed to break down high-level goals.

1.  **Analyze**: Coordinator receives a job.
2.  **Decompose**: It creates sub-tasks.
3.  **Delegate**: It calls `launch_subagent(agent_id: "coder", task_title: "...")`.
4.  **Wait/Synthesize**: It monitors sub-tasks and combines results.

### Agents as Tools
You can expose any agent as a tool in a chat session using `AgentAsTool`:

```swift
let researcher = ResearchAgent()
let tool = AgentAsTool(agent: researcher, jobQueueContext: jobQueue)
// Now the LLM can "call" the researcher as if it were a function.
```

---

## 5. Running the Engine

### Initialization
```swift
let engine = try await MonadEngine(
    persistenceService: persistence,
    embeddingService: embedding,
    llmService: llm,
    workspaceRoot: rootURL
)
```

### Starting the Job Runner
The `JobRunnerService` must be run in a background task:

```swift
Task {
    try await engine.jobRunner.run()
}
```

### Queuing a Task
```swift
let job = Job(
    sessionId: session.id,
    title: "Write a weather report",
    agentId: "default"
)
try await persistence.saveJob(job)
// The JobRunner will pick this up automatically.
```

---

## 6. Best Practices

1.  **Small, Specialized Agents**: Instead of one "God Agent", create specialized agents (Coder, Auditor, Researcher).
2.  **Use Task Trees**: Always set `parentId` when launching sub-agents so you can track the origin of work.
3.  **Atomic Tools**: Ensure tools are idempotent and handle errors gracefully.
4.  **Shared Memory**: Encourage agents to use `create_memory` to persist important findings across turns.

---

## 7. Troubleshooting

- **Segmentation Faults**: Often caused by circular dependencies in `DependencyKey` definitions or actor reentrancy.
- **Job Not Starting**: Ensure the `JobRunnerService` is actually running and the `agentId` in the job matches a registered agent.
- **Missing Context**: Verify the `ContextManager` is properly hydrated for the session.
