# State Stores

State stores in MonadCore (`Sources/MonadCore/Stores/`) provide thread-safe, actor-based caching layers that sit between high-traffic API controllers and the database layer.

## Overview

Stores differ from "Managers" (`SessionManager`, `WorkspaceManager`) in that they are mostly simple caching layers for the API, whereas Managers orchestrate deep domain logic, component initialization, and cross-cutting concerns.

### `WorkspaceStore`

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

## Deprecated Stores

### `SessionStore`

The `SessionStore` was removed. Its responsibilities were fully subsumed by `SessionManager`, which already maintains an active dictionary of `sessions: [UUID: Timeline]` and handles all session database reads and writes.

Using `SessionManager` is preferred for all session operations because session orchestration involves much more than just database synchronization (e.g. setting up `ContextManager`, `ToolExecutor`, and tracking tool sessions).
