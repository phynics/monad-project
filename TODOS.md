# TODOs — Agent Instances & Timeline Redesign

Suggestions from design session. Curate and prioritize as needed.

---

## Data Models

- [ ] **New: `AgentInstance` model** (`MonadShared` or `MonadCore/Models/Database/`)
  - Fields: `id`, `name`, `description`, `primaryWorkspaceId: UUID?`, `privateTimelineId: UUID`, `lastActiveAt`, `createdAt`, `updatedAt`, `metadata: [String: AnyCodable]`
  - No prompt fields — instructions live in workspace files
  - `composedInstructions` computed by reading workspace files at runtime

- [ ] **Modify `Timeline`**
  - Add: `attachedAgentInstanceId: UUID?`
  - Add: `isPrivate: Bool` (default `false`)
  - Add: `ownerAgentInstanceId: UUID?` (set when `isPrivate = true`)
  - Remove: `primaryWorkspaceId` (moved to `AgentInstance`)

- [ ] **Modify `Message`**
  - Add: `agentInstanceId: UUID?` (nil for human/CLI messages)

- [ ] **Modify `MSAgent`** — demote to template-only role
  - Add optional: `workspaceFilesSeed: [String: String]?` — filename → content for seeding `Notes/` on instance creation
  - Consider renaming to `AgentTemplate` for clarity (breaking change, defer)

---

## Database

- [ ] **Migration v32**
  - Create `agentInstances` table
  - Alter `timelines`: add `attachedAgentInstanceId`, `isPrivate`, `ownerAgentInstanceId`; handle existing `primaryWorkspaceId` rows
  - Alter `conversationMessages`: add `agentInstanceId`
  - Migration strategy for existing timelines: set `primaryWorkspaceId = nil` (or create a stub AgentInstance per timeline that has one — decide which)
  - Add `remoteDepth INTEGER DEFAULT 0` to `conversationMessages` (plumbing for future cross-agent recursion guard)

- [ ] **New store protocol: `AgentInstanceStoreProtocol`**
  - `saveAgentInstance`, `fetchAgentInstance(id:)`, `fetchAllAgentInstances()`, `deleteAgentInstance(id:)`, `fetchAgentInstances(attachedTo timelineId:)`

---

## Services

- [ ] **New: `AgentInstanceManager` actor**
  - `createInstance(from template: MSAgent?, name: String, description: String) async throws -> AgentInstance`
    - Creates private timeline atomically (transaction)
    - Seeds workspace files from template if provided
    - Logs creation event to private timeline as `.system` message
  - `attach(agentId: UUID, to timelineId: UUID) async throws`
    - Idempotent: if same agent already attached, no-op (no error)
    - Fails if a *different* agent is attached (caller must detach first or use force)
    - On fetch/attach: if `attachedAgentInstanceId` references a deleted agent, null it and log warning
    - Sets `timeline.attachedAgentInstanceId`
    - Logs `[ATTACH] timeline "{title}" ({id})` to agent's private timeline (no generation trigger)
  - `detach(agentId: UUID, from timelineId: UUID) async throws`
    - Clears `timeline.attachedAgentInstanceId`
    - Logs `[DETACH] timeline "{title}" ({id})` to agent's private timeline
  - `getAttachedAgent(for timelineId: UUID) async -> AgentInstance?`
    - If `attachedAgentInstanceId` references missing agent: null the field, log warning, return nil
  - `getTimelines(attachedTo agentId: UUID) async throws -> [Timeline]`
  - `deleteInstance(id: UUID, force: Bool) async throws` — returns 409 if attached and `force == false`

- [ ] **Modify `TimelineManager`** — workspace context source changes
  - Replace `timeline.primaryWorkspaceId` lookup with `agentInstance.primaryWorkspaceId`
  - `setupTimelineComponents` receives optional `AgentInstance` (nil = no agent / passthrough)
  - When agent changes on a timeline, tear down and rebuild context manager + tool manager

- [ ] **Modify `ContextManager`** — instructions from workspace files
  - Load `Notes/system.md` as agent system instructions (high-priority section, replaces hardcoded `DefaultInstructions` when present)
  - Load `Notes/persona.md` as persona overlay section
  - Falls back to `DefaultInstructions` when no `system.md` exists
  - Inject private timeline ID into context so agent is aware of it ("Your private timeline: `{id}`")

- [ ] **Modify `ChatEngine` / chat endpoint** — strict mode
  - Return `422` if `timeline.attachedAgentInstanceId == nil` (Q2-B strict mode)
  - Store `agentInstanceId` on generated assistant messages
  - Pull system instructions from agent's workspace rather than a fixed prompt

---

## Agent Tools (new system tools, provenance `[Agent]`)

- [ ] **`timeline_list`**
  - Returns non-private timelines: `id`, `title`, `attachedAgentName?`, `updatedAt`, `messageCount`
  - Parameters: `filter` (active|archived|all), `limit` (default 20)

- [ ] **`timeline_peek`**
  - Returns last N messages from any non-private timeline
  - Parameters: `timelineId`, `lastN` (default 10)
  - Forbidden on private timelines not owned by calling agent (403)

- [ ] **`timeline_send`**
  - Posts a `.user` role message to target timeline
  - Works on agent-less timelines (queued for next attaching agent)
  - Parameters: `timelineId`, `message`
  - Sets `remoteDepth` = caller's `remoteDepth + 1`; reject if > 5
  - Returns: `{ messageId }`

---

## API Endpoints

- [ ] `POST   /api/agent-instances` — create instance
- [ ] `GET    /api/agent-instances` — list all instances
- [ ] `GET    /api/agent-instances/{id}` — get instance
- [ ] `PATCH  /api/agent-instances/{id}` — update name/description/workspace
- [ ] `DELETE /api/agent-instances/{id}` — delete (409 if attached without `?force=true`)
- [ ] `GET    /api/agent-instances/{id}/private-timeline` — get agent's private timeline info
- [ ] `GET    /api/agent-instances/{id}/timelines` — list timelines this agent is attached to
- [ ] `POST   /api/timelines/{id}/attach` — attach agent `{ agentInstanceId }`
- [ ] `DELETE /api/timelines/{id}/attach` — detach agent
- [ ] `GET    /api/timelines/{id}/attach` — who is attached?
- [ ] Modify `GET /api/timelines` — add `includePrivate` query param (default false)

---

## CLI

- [ ] **`LocalConfig`**: add `lastAgentInstanceId: String?`
- [ ] **Startup flow** (`CLISessionManager`):
  - After resuming timeline, if `attachedAgentInstanceId` is set — show agent name in prompt
  - If timeline exists but no agent → "No agent attached. Select one: [list] / Skip" (Q2-B: skip is unavailable unless passthrough mode added later)
- [ ] **Agent detach event** — handle `agentDetached` in stream: "Agent '{name}' detached. Attach another? [Y/n]"
- [ ] **New slash commands**:
  - `/agent list` — list all instances
  - `/agent create [template-name]` — create from MSAgent template (interactive)
  - `/agent use <id|name>` — attach to current timeline (detaches previous if different)
  - `/agent info` — show currently attached agent
  - `/agent private [id|name]` — read last N messages from agent's private timeline
- [ ] **`ChatREPL`**: display agent name in prompt prefix, e.g. `[Coder] > `

---

## Open Questions / Decisions

- [X] **Workspace file convention** — where do instructions live?
  - Option A: `Notes/system.md`, `Notes/persona.md` (reuses existing Notes injection)
  - Option B: `Instructions/` directory at workspace root (separate from Notes)
  - We choose Option A.

- [ ] **`MSAgent` rename** — rename to `AgentTemplate` eventually to reflect its role? Flag as future breaking change.

- [X] **Private timeline listing in CLI** — `/agent private` should show a scrollable history view; decide if this needs a dedicated screen or reuses existing history display.
  - We choose to reuse existing history display.

- [X] **Passthrough mode** — even with Q2-B strict, there may be value in a server-level `allowPassthrough` flag for development/testing. Decision: add config flag or hardcode strict?
  - We choose to allow hardcoded strict.

- [ ] **`timeline_send` to private timelines** — currently allowed (cross-agent inbox). Should there be an opt-in `acceptsRemoteMessages: Bool` on AgentInstance? Or always open?

---

## Future (Out of Scope Now — Noted for Architecture Awareness)

- [ ] Wakeup triggers: `metadata.wakeupTriggers` — `onPrivateMessage`, `onSchedule (cron)`, `onMention`
- [ ] Cross-agent capability advertisement via `metadata.capabilities: [String]`
- [ ] Private timeline summarization — long-term agent memory via existing `isSummary` mechanism
- [ ] `remoteDepth` enforcement for cross-agent send recursion guard
