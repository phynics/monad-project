# State Stores

State stores in MonadCore (`Sources/MonadCore/Stores/`) provide thread-safe, actor-based caching layers that sit between high-traffic API controllers and the database layer.

## Persistence Stores

Persistence stores (`Sources/MonadCore/Services/Database/`) define the interface for long-term storage of domain entities. `MonadServer` provides a `PersistenceService` that implements all of these protocols using GRDB and SQLite.

### 1. `TimelineStore`
Manages the lifecycle of conversation sessions.
- **API**: `saveTimeline`, `fetchTimeline`, `fetchAllTimelines`, `deleteTimeline`, `pruneTimelines`.

### 2. `MessageStore`
Handles the storage and retrieval of chat history.
- **API**: `saveMessage`, `fetchMessages`, `deleteMessages`, `pruneMessages`.

### 3. `MemoryStore`
The persistent layer for the context engine's semantic memories.
- **API**: `saveMemory`, `fetchMemory`, `searchMemories`, `deleteMemory`, `vacuumMemories`.

### 4. `AgentInstanceStore`
Manages runtime agent identities and their private workspace/timeline links.
- **API**: `saveAgentInstance`, `fetchAgentInstance`, `fetchAllAgentInstances`, `deleteAgentInstance`.

### 5. `AgentTemplateStore`
Stores the static blueprints used to create new agents.
- **API**: `saveAgentTemplate`, `fetchAgentTemplate`, `fetchAllAgentTemplates`.

### 6. `WorkspaceStore` (Persistence)
Note: There is a `WorkspacePersistenceProtocol` for DB access and a `WorkspaceStore` actor for memory caching.
- **Persistence API**: `saveWorkspace`, `fetchWorkspace`, `fetchAllWorkspaces`, `deleteWorkspace`.

### 7. `ClientStore`
Tracks remote client identities (e.g., your laptop running the CLI).
- **API**: `saveClient`, `fetchClient`, `fetchAllClients`, `deleteClient`.

### 8. `BackgroundJobStore`
Manages asynchronous tasks scheduled for agent execution.
- **API**: `saveJob`, `fetchJob`, `fetchAllJobs`, `deleteJob`, `dequeueNextJob`.

---

## Caching Stores

These stores live in `Sources/MonadCore/Stores/` and provide thread-safe, actor-based caching layers that sit between high-traffic API controllers and the database layer.

### `WorkspaceStore` (Cache)

`WorkspaceStore` is the primary caching layer for hydrated workspace instances (`WorkspaceProtocol`).

It bridges the gap between the lightweight data-only `WorkspaceReference` stored in the database and the active, functional `WorkspaceProtocol` that can read/write files and execute tools.

**Primary Consumer:** `FilesAPIController` uses this store on every file read/write request to avoid repeatedly hydrating remote workspaces from their database references.

**API Surface:**
- `createWorkspace(uri:hostType:rootPath:ownerId:) -> WorkspaceProtocol` — Persists a new workspace reference and caches the hydrated instance.
- `getWorkspace(id: UUID) -> WorkspaceProtocol?` — Retrieves a cached instance.
- `reloadWorkspace(id: UUID)` — Forces a fetch from persistence and re-hydrates the instance.
- `unloadWorkspace(id: UUID)` — Removes a workspace from the memory cache (leaving it in the database).
- `deleteWorkspace(id: UUID)` — Removes a workspace from both the memory cache and the database.

> **Note on Initializer:** The store currently loads all workspaces greedily from the database upon initialization. If the workspace volume grows significantly, this should be refactored to a lazy-loading cache.

## Removed Stores

### `SessionStore` (removed)

The `SessionStore` was removed. Its responsibilities were fully subsumed by `TimelineManager`, which already maintains an active dictionary of `timelines: [UUID: Timeline]` and handles all timeline database reads and writes.

Use `TimelineManager` for all timeline operations — it covers much more than database sync (context manager setup, tool executor lifecycle, workspace resolution, etc.).
