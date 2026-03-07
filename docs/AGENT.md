# Agents

Monad's agent system distinguishes between two types:

- **`MSAgent`** — A static template that defines initial instructions, persona, and workspace seed files.
- **`AgentInstance`** — A live, persistent runtime entity created from a template. Has its own workspace, private timeline, and identity.

---

## MSAgent (Template)

**Location:** `Sources/MonadShared/SharedTypes/MSAgent.swift`

```swift
public struct MSAgent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public var systemPrompt: String
    public var personaPrompt: String?
    public var guardrails: String?
    public var workspaceFilesSeed: [String: String]?
    var composedInstructions: String { /* systemPrompt + personaPrompt + guardrails */ }
}
```

**Managed by:** `MSAgentRegistry` (`Sources/MonadCore/Services/MSAgents/MSAgentRegistry.swift`)

**API:** `GET/POST/PATCH/DELETE /api/msAgents`

MSAgents are seed templates — they are consumed at agent instance creation time and not referenced again at runtime.

---

## AgentInstance (Runtime Entity)

**Location:** `Sources/MonadShared/SharedTypes/AgentInstance.swift`

```swift
public struct AgentInstance: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var description: String
    public var primaryWorkspaceId: UUID?    // Private workspace (Notes/ directory)
    public let privateTimelineId: UUID      // Internal monologue / cross-agent inbox
    public var lastActiveAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: AnyCodable]
}
```

**Managed by:** `AgentInstanceManager` (`Sources/MonadCore/Services/Agents/AgentInstanceManager.swift`)

**API:** `GET/POST/PATCH/DELETE /api/agents`, `/api/agents/:id/attach/:timelineId`

### Key Behaviors

- **Self-contained after creation**: Instructions are loaded at runtime from `Notes/system.md` in the agent's private workspace, not from the original template.
- **Multi-timeline**: An agent can be attached to multiple timelines simultaneously.
- **Exclusive attachment**: Each timeline holds at most one attached agent at a time.
- **Private timeline**: `isPrivate: true` — used for internal monologue and cross-agent communication. Excluded from general listing.
- **Dangling reference cleanup**: If `attachedAgentInstanceId` references a deleted agent, it is cleared automatically on access.

### Attachment Rules

```
attach(agentId:, to: timelineId)  — idempotent if same agent; fails if different agent attached
detach(agentId:, from: timelineId) — no-op if agent not attached
```

---

## Creating an Agent Instance

### Via API

```http
POST /api/agents
{
  "name": "Research Agent",
  "description": "Specializes in searching and summarizing information.",
  "msAgentId": "uuid"   // optional — seeds workspace from template
}
```

### Via Code

```swift
@Dependency(\.agentInstanceManager) var agentInstanceManager

let instance = try await agentInstanceManager.createInstance(
    from: template,          // optional MSAgent seed
    name: "Research Agent",
    description: "Specializes in searching and summarizing information."
)

// Attach to a timeline
try await agentInstanceManager.attach(agentId: instance.id, to: timeline.id)
```

**What `createInstance` does atomically:**
1. Creates workspace directory at `<workspaceRoot>/agents/<instanceId>/Notes/`
2. Seeds `Notes/system.md` from `MSAgent.composedInstructions` (or custom `workspaceFilesSeed`)
3. Creates a private timeline (`isPrivate: true`, `ownerAgentInstanceId = instanceId`)
4. Persists workspace reference, private timeline, and agent instance

---

## Agent Identity in Prompts

When an agent is attached to a timeline, the prompt pipeline injects two additional context sections automatically (via `ChatEngine` → `LLMService.buildContext`):

### AgentContext (priority 95)

Injected between System Instructions and Context Notes:

```
## Your Identity
You are **<name>**.
Description: <description>
Currently operating on timeline: "<title>"
Your private workspace contains your persistent memory (Notes/ directory).
```

### System Instructions

`TimelineManager.getAgentSystemInstructions(for:)` reads `Notes/system.md` from the agent's workspace and passes it as `systemInstructions`, replacing the default `DefaultInstructions.system()`.

### TimelineContext (priority 72)

Injected between Workspaces and Chat History:

```
## Current Timeline
- ID: `<uuid>`
- Title: <title>
```

---

## Inter-Agent Communication

Agents communicate through **timeline tools**:

| Tool | Description |
|:-----|:------------|
| `timeline_list` | Discover non-private timelines and which agents are active on them |
| `timeline_peek` | Read recent messages from another timeline |
| `timeline_send` | Post a message to another timeline |

**Location:** `Sources/MonadCore/Services/Tools/Timeline/`

### Coordinator Pattern

1. Coordinator receives a high-level goal on its timeline
2. Creates and attaches sub-agent instances
3. Delegates by posting to sub-agent timelines via `timeline_send`
4. Monitors sub-agents via `timeline_peek`
5. Synthesizes results

### MSAgentAsTool

Expose an MSAgent template as a directly callable tool:

```swift
let tool = MSAgentAsTool(agent: template, jobQueueContext: jobQueue)
// LLM can call this agent as if it were a function
```

**Location:** `Sources/MonadCore/Services/Tools/MSAgent/MSAgentAsTool.swift`

---

## CLI Commands

```
/agent                        Show attached agent info
/agent list                   List all agent instances
/agent attach <id>            Attach agent to current timeline (prefix match supported)
/agent detach                 Detach current agent
/agent create <name> <desc>   Create a new agent instance
```

---

## API Reference

### Agent Instances (`/api/agents`)

| Method | Path | Description |
|:-------|:-----|:------------|
| `GET` | `/agents` | List all instances |
| `POST` | `/agents` | Create instance (`name`, `description`, optional `msAgentId`) |
| `GET` | `/agents/:id` | Get instance |
| `PATCH` | `/agents/:id` | Update instance |
| `DELETE` | `/agents/:id` | Delete (`?force=true` to force-detach) |
| `POST` | `/agents/:id/attach/:timelineId` | Attach to timeline |
| `DELETE` | `/agents/:id/attach/:timelineId` | Detach from timeline |
| `GET` | `/agents/:id/timelines` | List attached timelines |

### MSAgent Templates (`/api/msAgents`)

| Method | Path | Description |
|:-------|:-----|:------------|
| `GET` | `/msAgents` | List all templates |
| `POST` | `/msAgents` | Create template |
| `GET` | `/msAgents/:id` | Get template |
| `PATCH` | `/msAgents/:id` | Update template |
| `DELETE` | `/msAgents/:id` | Delete template |

---

## Best Practices

1. **Small, focused agents**: Create agents with specific roles (Researcher, Coder, Auditor) rather than one general-purpose agent.
2. **Persistent Notes**: Instruct agents to update `Notes/` files with findings so state persists across timelines and restarts.
3. **Use the private timeline**: Log reasoning and plans to the agent's private timeline for observability.
4. **System instructions live in the workspace**: Edit `Notes/system.md` directly to update an agent's behavior at runtime without recreating the instance.

---

## Troubleshooting

- **"No agent attached to timeline"**: The chat endpoint requires an agent before streaming. Attach one via `/api/agents/:id/attach/:timelineId` or `/agent attach <id>`.
- **Instructions not updating**: `system.md` is re-read on every turn — edit it in the agent's workspace for immediate effect.
- **Dangling reference warning**: If you see a log warning about clearing a dangling agent reference, the timeline was referencing a deleted agent instance. This is auto-repaired.
