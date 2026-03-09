# Workspaces

A **Workspace** is a secure, addressable execution environment where tools operate. It defines a root path, trust level, and set of available tools. Workspaces unify local execution (user's machine) and remote execution (server) behind a consistent interface.

---

## Model

**Location:** `Sources/MonadShared/SharedTypes/WorkspaceReference.swift`

`WorkspaceReference` is the lightweight metadata record stored in the database:

```swift
public struct WorkspaceReference: Codable, Sendable, Identifiable {
    public var id: UUID
    public var uri: WorkspaceURI
    public var hostType: HostType           // .server, .client
    public var rootPath: String?
    public var ownerId: UUID?
    public var tools: [WorkspaceToolDefinition]
    public var contextInjection: String?
    public var trustLevel: TrustLevel       // .full, .restricted
}
```

`WorkspaceProtocol` is the functional interface (file I/O, tool execution) hydrated from `WorkspaceReference` at runtime by `WorkspaceFactory`.

---

## Workspace Types

| Host Type | Description | Location | Used For |
|:----------|:------------|:---------|:---------|
| `.server` | Local disk path on the server | Server disk | Agent workspaces, attached project dirs |
| `.client` | Remote environment on the user's machine | Client machine | IDE integrations, client-hosted tools (RPC) |

### Workspace URI Types

```swift
public enum WorkspaceURI {
    case local(path: String)            // file:///path/to/dir
    case agentWorkspace(UUID)           // monad://agent/<id>
    case clientWorkspace(clientId: UUID, path: String)
    // ...
}
```

### Trust Levels

| Level | Behavior |
|:------|:---------|
| `.full` | Operations execute immediately |
| `.restricted` | Operations require per-action approval (future) |

---

## Agent vs. Attached Workspaces

**Agent Primary Workspace:**
- Created automatically when an `AgentInstance` is created
- URI: `WorkspaceURI.agentWorkspace(instanceId)`
- Contains `Notes/` directory with `system.md` and other persistent files
- Persists across timeline attachments and restarts

**Attached Workspaces:**
- Shared project directories attached to a specific timeline
- The CLI **automatically attaches** the current working directory on startup as a read-only workspace.
- Additional workspaces can be attached via `/workspace attach` or API.
- Can be server-side (`hostType: .server`) or client-side (`hostType: .client`)
- Detaching removes their tools from the timeline

---

## Tool Execution Flow

### 1. Discovery

When a timeline session starts, `TimelineToolManager` aggregates tools from:
1. **System Tools** — Built-in capabilities (`system_memory_search`, etc.)
2. **Agent Primary Workspace** — Filesystem tools scoped to the agent's `Notes/` dir
3. **Attached Workspaces** — Project filesystem tools and any custom tool definitions

### 2. Routing

When the LLM calls a tool (e.g. `read_file(path: "main.swift")`):

```
Tool Call
    │
    ▼
ToolRouter.route()
    │
    ├─ Workspace target specified? → route to that workspace
    │
    └─ No target?
           ├─ Tool in primary workspace? → primary
           ├─ Tool in attached workspace? → first matching attached
           └─ Not found → ToolError
```

**Location:** `Sources/MonadCore/Services/Tools/ToolRouter.swift`

### 3. Execution

- **Server tools** (`.server` host type): Executed directly by `ToolExecutor` on the server.
- **Client tools** (`.client` host type): `ToolRouter` throws `ToolError.clientExecutionRequired`. `ChatEngine` pauses generation and emits a `toolExecution` event. The client executes locally and resumes the stream by posting `toolOutputs`.

### Write Access Elevation

Client-side workspaces are attached with `trustLevel: .readOnly` by default. If the LLM needs to modify files (e.g. `write_file`, `edit_file`), it must first call the `request_write_access(reason:)` tool.

1. LLM calls `request_write_access`
2. Server routes to client
3. CLI prompts user: "Grant full write access? [y/N]"
4. If granted, CLI updates workspace to `trustLevel: .full` and returns success
5. LLM can now call write tools on that workspace

---

## Security & Isolation

**Path jailing:** All filesystem tools sanitize paths via `PathSanitizer`. Attempts to access `../` or absolute paths outside the workspace root are blocked.

**State isolation:** Each timeline has its own `ContextManager` and `ToolExecutor`, preventing cross-talk between concurrent conversations.

**Trust levels:**
- `.readOnly`: Only read tools (ls, cat, grep, etc) are available.
- `.full`: All tools including write/delete are available.

---

## Workflows

### Auto-Attaching Project Directory

When you start `monad chat`, the CLI:

1. Resolves the absolute path of the current directory.
2. Registers/Finds a client-side workspace for this path on the server.
3. Attaches it to the current timeline with `.readOnly` trust.
4. Syncs the standard read-only toolset.

### Client-Managed Workspaces (IDE/Remote)

For IDE integrations or remote environments:

1. Client registers its identity via `POST /api/clients`
2. Client declares a `.client` workspace via `POST /api/workspaces`
3. Client attaches the workspace to a timeline
4. When the LLM calls a tool in this workspace, `ToolRouter` throws `clientExecutionRequired`
5. The server-sent event prompts the client to execute locally and return the result

---

## WorkspaceStore

`WorkspaceStore` (in `Sources/MonadCore/Stores/WorkspaceStore.swift`) is an actor cache that maps workspace IDs to hydrated `WorkspaceProtocol` instances.

**Primary consumer:** `FilesAPIController` — avoids re-hydrating remote workspaces on every file request.

**API:**
- `createWorkspace(uri:hostType:rootPath:ownerId:)` — Persist + cache
- `getWorkspace(id:)` — Retrieve cached instance
- `reloadWorkspace(id:)` — Force re-hydration from DB
- `unloadWorkspace(id:)` — Remove from cache (keep in DB)
- `deleteWorkspace(id:)` — Remove from cache and DB

---

## API Reference

| Method | Path | Description |
|:-------|:-----|:------------|
| `GET` | `/workspaces` | List all workspaces |
| `POST` | `/workspaces` | Register a new workspace |
| `GET` | `/workspaces/:id` | Get workspace details and tool list |
| `PATCH` | `/workspaces/:id` | Update workspace (e.g. elevation to `.full`) |
| `GET` | `/workspaces/:id/files` | List files |
| `GET` | `/workspaces/:id/files/:path` | Read a file |
| `PUT` | `/workspaces/:id/files/:path` | Write a file |
| `GET` | `/sessions/:id/workspaces` | List workspaces attached to a timeline |
| `POST` | `/sessions/:id/workspaces` | Attach workspace to timeline |
| `DELETE` | `/sessions/:id/workspaces/:wsId` | Detach workspace from timeline |
| `POST` | `/sessions/:id/workspaces/:wsId/restore` | Re-attach a disconnected workspace |

---

## CLI Commands

```
/workspace list              List attached workspaces
/workspace attach <id>       Attach a workspace to the current timeline
/workspace detach <id>       Detach a workspace
/ls [path]                   List files in workspace
/cat <path>                  Read a file
/write <path>                Write a file
/edit <path>                 Edit a file
/rm <path>                   Remove a file
```

---

## Tool Provenance

Tools are labeled so the LLM understands their context:

| Label | Example |
|:------|:--------|
| `[System]` | `system_memory_search [System]` |
| `[Workspace: Name]` | `read_file [Workspace: MyProject]` |
| `[Session]` | Dynamically added tools |

**Implementation:** `AnyTool` wrapper carries an optional `provenance` string. `TimelineToolManager` formats tool definitions with labels when assembling the tools context section.
