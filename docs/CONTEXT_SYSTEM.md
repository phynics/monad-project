# Monad Context System

This document explains how Monad gathers, filters, and assembles context for the Large Language Model (LLM).

## 1. Context Assembly Pipeline

The `ChatEngine` orchestrates the context gathering process before every LLM turn. It uses the `ContextManager` service to gather relevant context, then uses the `@ContextBuilder` DSL from the `MonadPrompt` module to construct the final prompt.

### Flow Overview

```mermaid
flowchart LR
    Query[User Query] --> CM[ContextManager]
    CM --> Augment[Augment with History]
    Augment --> Tags[Generate Tags]
    Tags --> Embed[Create Embedding]
    Embed --> Search{Parallel Search}

    Search --> Semantic[Semantic Search]
    Search --> TagBased[Tag Search]

    Semantic --> Rank[Re-Rank Results]
    TagBased --> Rank

    Rank --> Notes[Read Notes/]
    Notes --> Builder[@ContextBuilder]

    Builder --> Sections[Assemble Sections]
    Sections --> Budget[Apply Token Budget]
    Budget --> Prompt[Final Prompt]
```

### Components of a Prompt

The final prompt consists of sections assembled with the `@ContextBuilder` DSL:

1. **System Instructions** — Base persona and behavioral rules (from `DefaultInstructions.swift`)
2. **Context Notes** — Files from the `Notes/` directory in the Primary Workspace
3. **Memories** — Relevant long-term facts retrieved via semantic search
4. **Tools** — Definitions of available capabilities, formatted with workspace provenance
5. **Chat History** — Recent messages from the current session (automatically truncated)
6. **User Query** — The current user input

**Priority Ordering:**
- Higher priority sections receive token allocation first
- Typical priorities: System (100) → Notes (90) → Memories (80) → Tools (70) → History (60) → Query (10)

---

## 2. Context Gathering Process

### ContextManager Service

`ContextManager` is an actor that orchestrates RAG (Retrieval-Augmented Generation).

**Location:** `Sources/MonadCore/Services/Context/ContextManager.swift`

**Key Method:**
```swift
func gatherContext(
    for query: String,
    history: [Message],
    limit: Int,
    tagGenerator: ((String) async throws -> [String])?
) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error>
```

**Return Type:** Streaming events for progress tracking

**Events:**
- `.augmenting` — Augmenting query with conversation history
- `.tagging` — Generating search tags via LLM
- `.embedding` — Creating query embedding
- `.searching` — Executing parallel searches
- `.ranking` — Re-ranking combined results
- `.complete(ContextData)` — Context ready

### Search Strategy

The system uses a **hybrid search** approach combining:

1. **Semantic Search** (Vector-based):
   - Query augmented with recent conversation history
   - Embedding generated via `EmbeddingService`
   - Vector search via `VectorStore` (USearch)
   - Returns top 2N results (doubled for re-ranking)
   - Minimum similarity threshold: 0.35

2. **Tag-based Search** (Metadata):
   - LLM generates relevant tags from query
   - Direct tag match against memory tags
   - Fast retrieval via database index

3. **Re-Ranking**:
   - `ContextRanker` combines semantic + tag results
   - Uses cosine similarity for scoring
   - Tag matches receive boost
   - Final top N memories selected

**Location:** `Sources/MonadCore/Services/Context/ContextRanker.swift`

### Parallel Execution

Searches execute in parallel for performance:

```swift
async let semanticTask = persistenceService.searchMemories(
    embedding: embedding,
    limit: limit * 2,
    minSimilarity: 0.35
)

async let tagTask = persistenceService.searchMemories(
    matchingAnyTag: searchTags
)

let (semanticResults, tagResults) = try await (semanticTask, tagTask)
```

---

## 3. Context Notes (`Notes/` Directory)

Monad uses a **filesystem-based approach** for long-term project context and persona storage.

### Design Philosophy

Rather than storing context in database records, Monad uses plain markdown files that:
- Are human-readable and editable
- Can be version-controlled
- Persist across sessions
- Can be updated by the LLM via `write_to_file` tool

### Directory Structure

- **Location**: Every session has a `Notes/` directory in its Primary Workspace
- **Seeding**: New sessions initialized with:
  - `Welcome.md` — Introduction and usage guide
  - `Project.md` — Project-specific context (placeholder)

### RAG Integration

The `ContextManager.fetchAllNotes()` method:
1. Lists all `.md` files in `Notes/` directory
2. Reads file contents
3. Wraps in `ContextFile` objects with metadata
4. Returns as high-priority context

**Priority:** Context Notes receive priority 90 (higher than memories)

**Strategy:** Summarize if too large (uses utility LLM model)

### AI Modification

The LLM is instructed to **proactively update** these files:
- Store important state or refined instructions
- Update project context as it learns
- Create new notes for specific topics
- Organize information for future reference

**Example Instructions:**
```
You have access to a Notes/ directory in your workspace. Use write_to_file
to update notes as you learn about the user's project, preferences, or goals.
Keep notes organized and up-to-date.
```

---

## 4. The Agent Model

Agents provide high-level "profiles" that influence the prompt and behavior.

### Agent Components

**Agent Model** (`Sources/MonadCore/Models/Agents/Agent.swift`):
```swift
public struct Agent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let systemPrompt: String
    public let personaPrompt: String?
    public let guardrails: String?
    // ... timestamps, metadata
}
```

**Composed Instructions:**
- System prompt (base behavior)
- Persona prompt (character traits)
- Guardrails (safety and formatting constraints)

### Agent Registry

**Service:** `AgentRegistry` (`Sources/MonadCore/Services/Agents/AgentRegistry.swift`)

**Responsibilities:**
- Seed default agents (Default Assistant, Agent Coordinator)
- Load agents from persistence
- Provide agent lookup

**Default Agents:**
- **Default Assistant**: General-purpose conversational agent
- **Agent Coordinator**: Specialized for task decomposition and delegation

### Conversation Records (Timeline)

Conversation records are stored in `Timeline` (formerly `Timeline`).

**Model:** `Sources/MonadCore/Models/Database/Timeline.swift`

**Fields:**
- `id`, `title`, `createdAt`, `updatedAt`
- `isArchived`, `tags`
- `workingDirectory`
- `primaryWorkspaceId` — Reference to primary workspace
- `attachedWorkspaceIds` — JSON array of attached workspace IDs

**Persistence:** Managed via `TimelinePersistenceProtocol`

### Default Prompts

**Location:** `Sources/MonadCore/Services/Prompting/DefaultInstructions.swift`

Contains default system instructions, persona, and guardrails.

---

## 5. Prompt Engineering DSL (`MonadPrompt`)

Prompts are built using a type-safe `@ContextBuilder` result builder.

### Basic Usage

```swift
import MonadPrompt

let prompt = Prompt {
    SystemSection(
        priority: 100,
        content: systemInstructions,
        strategy: .keep
    )

    ContextNotesSection(
        priority: 90,
        notes: contextNotes,
        strategy: .summarize
    )

    MemorySection(
        priority: 80,
        memories: relevantMemories,
        strategy: .truncate(tail: true)
    )

    ToolSection(
        priority: 70,
        tools: availableTools,
        strategy: .keep
    )

    HistorySection(
        priority: 60,
        messages: chatHistory,
        strategy: .truncate(tail: false)
    )

    UserQuerySection(
        priority: 10,
        query: userQuery,
        strategy: .keep
    )
}

// Build messages with token budget
let messages = prompt.buildMessages(budget: 8000)
```

### Token Budgeting

The `TokenBudget` system ensures the generated prompt fits within the model's context window.

**Priority-based Allocation:**
1. Sections sorted by priority (highest first)
2. Tokens allocated to each section in order
3. Compression strategy applied if section exceeds available budget

**Compression Strategies:**

| Strategy | Behavior |
|:---------|:---------|
| `.keep` | Do not compress; drop section if no budget |
| `.truncate(tail: Bool)` | Clip text from start (`tail: false`) or end (`tail: true`) |
| `.summarize` | Use smaller LLM turn to produce a summary |
| `.drop` | Drop section entirely if budget exceeded |

**Token Estimation:**
- Each section implements `estimatedTokens` property
- Rough estimate: 1 token ≈ 4 characters
- More accurate estimation via `TokenEstimator` (uses tiktoken-style counting)

### Section Protocol

**Protocol:** `ContextSection` (`Sources/MonadPrompt/ContextSection.swift`)

```swift
public protocol ContextSection: Sendable {
    var estimatedTokens: Int { get }
    var priority: Int { get }
    var strategy: CompressionStrategy { get }

    func buildContent() async throws -> String
    func compress(to budget: Int) async throws -> String
}
```

**Custom Sections:**
Implement `ContextSection` to create custom prompt sections with specific compression logic.

---

## 6. Workspace & Tool Relationship

Tools are surfaced to the LLM with **provenance information** to help it reason about its environment.

### Tool Types by Provenance

| Provenance | Description | Example |
|:-----------|:------------|:--------|
| `[System]` | Global capabilities | `system_memory_search`, `system_web_search` |
| `[Workspace: Name]` | Workspace-specific tools | `read_file` in "MyProject" workspace |
| `[Session]` | Ephemeral session tools | Tools added dynamically to session |

**Implementation:**
- `AnyTool` wrapper includes optional `provenance` string
- `TimelineToolManager` formats tool definitions with labels
- LLM sees: `read_file [Workspace: MyProject] — Read a file from the workspace`

### Path Resolution

The LLM is instructed on how to handle paths across workspaces:

**Primary Workspace:**
- Paths are typically relative to the session root
- Example: `Notes/Project.md`

**Attached Workspaces:**
- Paths must be resolved relative to their respective roots
- LLM should specify workspace context when ambiguous
- `ToolRouter` resolves correct workspace automatically

**Security:**
- All paths jailed to workspace root via `PathSanitizer`
- Attempts to access `../` or absolute paths outside root are blocked
- `PathSanitizer.safelyResolve(path:, relativeTo:)` validates and resolves

### Client-Side Tools

Tools hosted by remote clients (e.g., IDE integrations):
- Execute only when corresponding `RemoteWorkspace` is healthy
- `ToolRouter` throws `ToolError.clientExecutionRequired` for delegation
- `ChatEngine` pauses, requests client execution
- Client executes and returns result
- `ChatEngine` feeds result back to LLM

**Example:** `edit_file` in a local IDE workspace
1. LLM requests `edit_file(path: "src/main.swift", ...)`
2. `ToolRouter` detects client-hosted workspace
3. Throws `ToolError.clientExecutionRequired(workspace, tool, params)`
4. `ChatEngine` emits `toolExecution` event with status `.clientRequired`
5. Client executes locally
6. Client sends result back to server
7. `ChatEngine` continues with result

---

## 7. Implementation Details

### ContextManager Initialization

`ContextManager` is created per-session by `TimelineManager`:

```swift
let contextManager = ContextManager(
    workspace: primaryWorkspace,
    agentId: agent.id
)
```

**Actor Isolation:** All state protected by actor isolation

**Caching:** TimelineManager maintains cache of ContextManagers (one per session)

### Gathering Context

When `ChatEngine` needs context:

```swift
let contextStream = try await contextManager.gatherContext(
    for: userQuery,
    history: recentHistory,
    limit: 10,
    tagGenerator: llmService.generateTags
)

var contextData: ContextData?
for try await event in contextStream {
    switch event {
    case .augmenting, .tagging, .embedding, .searching, .ranking:
        // Emit progress events
    case .complete(let data):
        contextData = data
    }
}
```

**ContextData:**
```swift
public struct ContextData: Sendable {
    public let notes: [ContextFile]
    public let memories: [Memory]
    public let augmentedQuery: String
    public let searchTags: [String]
}
```

### Building the Prompt

`ChatEngine` uses `LLMService.buildContext()` which internally uses `@ContextBuilder`:

```swift
let messages = try await llmService.buildContext(
    userQuery: query,
    contextNotes: contextData.notes,
    memories: contextData.memories,
    chatHistory: history,
    tools: availableTools,
    systemInstructions: agent.composedInstructions
)
```

**Note:** The `buildContext` method is a convenience wrapper. For custom prompt construction, use `@ContextBuilder` directly.

---

## Summary

Monad's context system provides:

- **Hybrid RAG**: Semantic search + tag-based search with re-ranking
- **Filesystem-based context**: Human-readable, version-controllable Notes/
- **Intelligent compression**: Truncation and summarization based on priority
- **Token budgeting**: Ensures prompts fit within model limits
- **Tool provenance**: Helps LLM reason about available capabilities
- **Streaming progress**: Real-time feedback during context gathering
- **Multi-workspace support**: Scoped tools and path resolution

The system is designed for transparency, debuggability, and flexibility, allowing the LLM to maintain deep context across long-running sessions while staying within token limits.
