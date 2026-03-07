# Timelines

A **Timeline** is the persistent conversation record between a user and an agent. It orchestrates context gathering, memory, and tool execution for each chat turn.

---

## Model

**Location:** `Sources/MonadCore/Models/Database/Timeline.swift`

```swift
public struct Timeline: Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var tags: String                      // JSON-encoded [String]
    public var workingDirectory: String?
    public var primaryWorkspaceId: UUID?
    public var attachedWorkspaceIds: String       // JSON-encoded [UUID]
    public var attachedAgentInstanceId: UUID?     // Agent driving this timeline
    public var isPrivate: Bool                   // True for agent internal timelines
    public var ownerAgentInstanceId: UUID?       // Set when isPrivate == true
}
```

**Formerly called:** `ConversationSession`

**Persistence:** `TimelinePersistenceProtocol`

**Manager:** `TimelineManager` (`Sources/MonadCore/Services/Timeline/TimelineManager.swift`)

---

## Types of Timelines

| Type | `isPrivate` | Purpose |
|:-----|:------------|:--------|
| User timeline | `false` | Normal conversation between user and agent |
| Agent private timeline | `true` | Agent internal monologue, cross-agent inbox |

Private timelines are excluded from `/api/sessions` listing and are created automatically with each agent instance.

---

## API

Route prefix: `/api/sessions`

| Method | Path | Description |
|:-------|:-----|:------------|
| `GET` | `/sessions` | List timelines (`?archived=true` for archived) |
| `POST` | `/sessions` | Create timeline (`{ "title": "..." }`) |
| `GET` | `/sessions/:id` | Get timeline |
| `PATCH` | `/sessions/:id` | Update title |
| `DELETE` | `/sessions/:id` | Delete timeline |
| `GET` | `/sessions/:id/messages` | Get messages (`?page=&perPage=`) |
| `POST` | `/sessions/:id/chat/stream` | Chat (SSE stream) |
| `GET` | `/sessions/:id/workspaces` | List attached workspaces |
| `POST` | `/sessions/:id/workspaces` | Attach workspace |
| `DELETE` | `/sessions/:id/workspaces/:wsId` | Detach workspace |
| `POST` | `/sessions/:id/workspaces/:wsId/restore` | Re-attach workspace |

---

## Chat Stream

`POST /api/sessions/:id/chat/stream`

**Requirements:** An agent instance must be attached to the timeline before streaming.

**Headers:** `Accept: text/event-stream`

**Request body:**
```json
{
  "message": "Hello",
  "toolOutputs": [
    { "toolCallId": "call_123", "output": "result text" }
  ]
}
```

`toolOutputs` is used to resume a turn that was paused for client-side tool execution.

---

## SSE Event Stream

The stream emits `ChatEvent` objects as JSON-encoded Server-Sent Events.

| Event Type | Description | Key Fields |
|:-----------|:------------|:-----------|
| `generationContext` | Turn start — once per request | `timelineId`, `agentId`, workspace info |
| `thought` | Hidden CoT reasoning (`<think>` tags) | `thought` |
| `thoughtCompleted` | End of reasoning phase | — |
| `delta` | User-facing text fragment | `content` |
| `toolCall` | LLM requesting a tool | `toolCallId`, `name`, `arguments` (streaming) |
| `toolExecution` | Tool status update | `toolCallId`, `name`, `status` (`attempting`/`success`/`failure`), `result` |
| `generationCompleted` | Turn complete | `message` (full `Message`), `responseMetadata` |
| `streamCompleted` | End of stream | — |
| `error` | Processing error | `error` |

**Consuming the stream:**
1. Accumulate `delta` events for user-facing content
2. Show `toolExecution` events for tool transparency
3. Optionally display `thought` events (hidden reasoning)
4. Parse final `Message` from `generationCompleted` for storage

---

## Chat Flow

```
User message
    │
    ▼
ChatAPIController.chatStream()
    │
    ├─ Verify agent attached (required)
    ├─ Load agent system instructions (Notes/system.md)
    │
    ▼
ChatEngine.chatStream()
    │
    ├─ Save user message to DB
    ├─ Fetch conversation history
    ├─ Gather RAG context (ContextManager)
    │
    ▼
LLMService.buildContext()
    │  (SystemInstructions → AgentContext → Notes → Memories
    │   → Tools → Workspaces → TimelineContext → History → Query)
    │
    ▼
LLMService.chatStream()  →  StreamingParser
    │                              │
    │                   Extract <think> tags (CoT)
    │                   Detect tool calls
    │
    ├─ Tool call requested?
    │       ├─ Server tool → ToolRouter.execute()
    │       └─ Client tool → emit toolExecution + pause (client resumes via toolOutputs)
    │
    ├─ Save assistant message (with agentInstanceId authorship)
    └─ Emit generationCompleted
```

---

## Timeline Tools

Agents can interact with other timelines using built-in tools:

| Tool | Description |
|:-----|:------------|
| `timeline_list` | List non-private timelines with their attached agents |
| `timeline_peek` | Read recent messages from another timeline |
| `timeline_send` | Post a message to another timeline |

**Location:** `Sources/MonadCore/Services/Tools/Timeline/`

---

## CLI Commands

```
/new                       Start a new timeline
/timeline info             Show current timeline info
/timeline list             List recent timelines
/timeline switch <id>      Switch to a timeline (prefix match)
```

---

## TimelineManager

`TimelineManager` is the actor that owns timeline lifecycle.

**Key responsibilities:**
- Create/fetch/list timelines
- Manage per-timeline component cache (`ContextManager`, `ToolRouter`, workspace state)
- Resolve attached agent and system instructions
- Cancel ongoing generation tasks
- Store debug snapshots for `/debug` command

**Location:** `Sources/MonadCore/Services/Timeline/TimelineManager.swift`
