# MonadClient & CLI

## MonadClient Library

`MonadClient` is the Swift library for communicating with `MonadServer`. It provides HTTP/SSE networking, Bonjour server discovery, and client-side tool execution.

**Location:** `Sources/MonadClient/`

**Dependencies:** MonadShared, Logging

### Configuration

```swift
let config = await ClientConfiguration.autoDetect(
    explicitURL: url,       // nil = auto-discover via Bonjour
    apiKey: "sk-...",
    verbose: false
)
let client = MonadClient(configuration: config)
```

**Auto-detection order:**
1. Explicit URL (flag or local config)
2. Bonjour/mDNS discovery (finds servers on local network)
3. Fallback to `localhost:8080`

### Client Facades

```swift
client.chat       // MonadChatClient — chat, messages, agent instances
client.workspace  // MonadWorkspaceClient — workspace management
```

### Key Client Operations

```swift
// Timelines
try await client.chat.listTimelines()
try await client.chat.createTimeline(title: "My Timeline")

// Agent instances
try await client.chat.listAgentInstances()
try await client.chat.createAgentInstance(name: "Researcher", description: "...")
try await client.chat.attachAgent(agentId: id, to: timelineId)
try await client.chat.detachAgent(agentId: id, from: timelineId)
try await client.chat.getAgentInstance(id: agentId)

// Chat streaming
let stream = try await client.chat.stream(timelineId: id, message: "Hello")
for try await event in stream { ... }

// Workspaces
try await client.workspace.attachWorkspace(id: wsId, to: timelineId)
```

### Client Registration

The CLI registers itself with the server so client-side tools (like `request_write_access`) can be routed back:

```swift
let identity = try await RegistrationManager.shared.ensureRegistered(client: client)
// Returns ClientIdentity with a stable clientId stored in local config
```

**API:** `POST /api/clients` (register), `DELETE /api/clients/:id` (unregister)

---

## MonadCLI

The interactive REPL and command-line tool for Monad.

**Location:** `Sources/MonadCLI/`

**Dependencies:** MonadClient, ArgumentParser

### Starting the CLI

```bash
swift run MonadCLI chat                    # Interactive REPL (default)
swift run MonadCLI chat --server http://...  # Explicit server URL
swift run MonadCLI chat --timeline <id>    # Resume a specific timeline
swift run MonadCLI status                  # Check server health
```

### Startup Sequence

1. Load local config (`LocalConfigManager`)
2. Auto-detect server URL (flag → local config → Bonjour → localhost)
3. Health check server
4. Register client identity (idempotent)
5. Check/show configuration screen if LLM not configured
6. Resolve timeline (explicit ID → last session → new)
7. Handle workspace re-attachment
8. **Auto-attach current directory** as a read-only client workspace
9. Restore last attached agent instance (from local config)
10. Start REPL

### Slash Command Reference

**Core:**

| Command | Description |
|:--------|:------------|
| `/help` | Show available commands |
| `/quit` (or `:q`) | Exit |
| `/status` | Show server status |
| `/config` | View/edit server configuration |
| `/debug` | Show rendered prompt and raw LLM output |
| `/cancel` | Cancel ongoing generation |
| `/new` | Start a new timeline |
| `/clear` | Clear terminal screen |

**Timeline:**

| Command | Description |
|:--------|:------------|
| `/timeline info` | Show current timeline info |
| `/timeline list` | List recent timelines |
| `/timeline switch <id>` | Switch to a timeline (prefix match) |

**Agent:**

| Command | Description |
|:--------|:------------|
| `/agent` | Show attached agent info |
| `/agent list` | List all agent instances |
| `/agent attach <id>` | Attach agent (prefix match supported) |
| `/agent detach` | Detach current agent |
| `/agent create <name> <desc>` | Create a new agent instance |

**Workspace:**

| Command | Description |
|:--------|:------------|
| `/workspace list` | List attached workspaces |
| `/workspace attach <id>` | Attach a workspace |
| `/workspace detach <id>` | Detach a workspace |

**Files:**

| Command | Description |
|:--------|:------------|
| `/ls [path]` | List files |
| `/cat <path>` | Read a file |
| `/write <path>` | Write a file |
| `/edit <path>` | Edit a file |
| `/rm <path>` | Remove a file |

**Memory & Jobs:**

| Command | Description |
|:--------|:------------|
| `/memory list` | List memories |
| `/memory add <content>` | Add a memory |
| `/memory search <query>` | Search memories |
| `/job list` | List background jobs |
| `/job add <title>` | Add a background job |

**System:**

| Command | Description |
|:--------|:------------|
| `/tool` | List available tools |
| `/client` | Show client info |
| `/prune` | Clean up old data |

### Local Configuration

`LocalConfigManager` persists CLI state between sessions:

```swift
// Stored at ~/.monad/config.json (or platform equivalent)
struct LocalConfig {
    var serverURL: String?
    var apiKey: String?
    var lastSessionId: String?        // Last active timeline ID
    var lastAgentInstanceId: String?  // Last attached agent ID
}
```

On startup, the CLI automatically restores the last timeline and agent instance.

### Tab Completion

The REPL supports tab completion for all slash commands (including aliases). Type `/` and press Tab to see available commands.
