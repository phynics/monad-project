# MonadCore: General-Purpose Agent Framework Guide

MonadCore is a modular, high-performance Swift framework for building and orchestrating autonomous AI agents. It provides a structured environment for agents to execute tasks, use tools, and coordinate with each other.

---

## 1. Core Concepts

### Agents
An **Agent** is a persistent entity defined by its instructions and persona, stored in the database.
- **`Agent` Model**: A `Codable` struct defining the agent's identity and prompt.
- **`AgentExecutor`**: The service that runs the agent's autonomous loop.

### Jobs (Tasks)
Execution is managed via **Jobs**.
- **Persistent**: Jobs are stored in the database and survive restarts.
- **Hierarchical**: Jobs can have a `parentId`, forming a task tree.
- **Status Tracking**: Pending, In-Progress, Completed, Failed, Cancelled.

### Orchestration
- **`ChatEngine`**: The unified engine for both interactive chat and autonomous agent loops.
- **`ContextBuilder`**: A declarative DSL for constructing prompts from history, memories, and tools.
- **`JobRunnerService`**: A background service that monitors the database and executes pending jobs.
- **`SessionManager`**: Manages the lifecycle of conversation sessions and their components.

---

## 2. Defining an Agent

Agents are defined as records in the database. You can create them programmatically or via CLI/API.

```swift
import MonadCore
import Foundation

let researcher = Agent(
    id: UUID(),
    name: "Research Agent",
    description: "Specializes in searching and summarizing information.",
    systemPrompt: """
    You are a Researcher. Your goal is to provide deep insights on any topic.
    Use the search tools extensively.
    """
)

// Persist the agent
try await persistenceService.saveAgent(researcher)
```

---

## 3. Customizing Execution

### ChatEngine
The `ChatEngine` drives the interaction. It uses `ContextBuilder` internally to construct prompts.

```swift
let stream = try await chatEngine.chatStream(
    sessionId: session.id,
    message: "Research this topic",
    tools: availableTools,
    systemInstructions: agent.composedInstructions
)
```

### ContextBuilder (Advanced)
If you are building a custom loop outside of `ChatEngine`, you can use `ContextBuilder` directly:

```swift
let prompt = await ContextBuilder {
    SystemInstructions("You are a custom agent")
    ChatHistory(messages)
    UserQuery("Hello")
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
let researcher = try await Agent.fetchOne(db, key: "researcher")
let tool = AgentAsTool(agent: researcher, jobQueueContext: jobQueue)
// Now the LLM can "call" the researcher as if it were a function.
```

---

## 5. Running the Framework

### Initializing the SessionManager
The `SessionManager` is the primary entry point for managing sessions and their tools.

```swift
import MonadCore
import Dependencies

// SessionManager uses @Dependency for shared services
let manager = SessionManager(
    workspaceRoot: URL(fileURLWithPath: "/path/to/workspaces")
)

// Create a new session
let session = try await manager.createSession(title: "My Session")
```

### Starting the Job Runner
The `JobRunnerService` is a `Service` and can be run in a `ServiceGroup` or manually:

```swift
let jobRunner = JobRunnerService()
Task {
    try await jobRunner.run()
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
