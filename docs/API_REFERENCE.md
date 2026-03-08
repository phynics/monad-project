# MonadServer API Reference

Base URL: `/api`

## Response Formats

### Standard Response
All successful responses return JSON with status 200/201.

---

## System Status

### Health Check
`GET /health`

Returns `OK` (text/plain) if the server is running.

### Detailed Status
`GET /status`

Returns detailed health status of all system components.

**Response Body:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "uptime": 12345,
  "components": {
    "database": {
      "status": "ok",
      "details": { "path": "/path/to/db.sqlite" }
    },
    "ai_provider": {
      "status": "ok",
      "details": { "provider": "openai", "model": "gpt-4" }
    }
  }
}
```

---

## Timelines (Sessions)

Route prefix: `/api/sessions`

### List Timelines
`GET /sessions`

**Query Parameters:**
- `page` (int, default: 1)
- `perPage` (int, default: 20)
- `archived` (bool, optional): Filter by archived status.

### Create Timeline
`POST /sessions`

**Body:**
```json
{
  "title": "Project Planning"
}
```

### Get Timeline
`GET /sessions/:id`

### Update Timeline
`PATCH /sessions/:id`

**Body:**
```json
{
  "title": "New Title"
}
```

### Delete Timeline
`DELETE /sessions/:id`

### Get Timeline Messages
`GET /sessions/:id/messages`

**Query Parameters:**
- `page` (int, default: 1)
- `perPage` (int, default: 50)

### Chat (Stream)
`POST /sessions/:id/chat/stream`

Requires an agent instance to be attached to the timeline before use.

**Headers:**
- `Accept: text/event-stream`

**Body:**
```json
{
  "message": "Hello",
  "toolOutputs": [...]
}
```
**Response:** Server-Sent Events (SSE) stream of `ChatEvent` objects.

Each event parses into a `ChatEvent` object:

```json
{
  "type": "thought",
  "content": null,
  "thought": "I should call a tool here...",
  "toolCalls": null,
  "error": null,
  "message": null,
  "responseMetadata": null,
  "toolExecution": null
}
```

**Known Event Types:**
- `generationContext`: Sent once at the start. Contains `ChatMetadata` (timelineId, agentId, workspace info).
- `thought`: The model's raw internal reasoning process.
- `thoughtCompleted`: Signals the reasoning phase has concluded.
- `delta`: The model's content output intended for the user.
- `toolCall`: JSON tool call signature delta.
- `toolExecution`: Asynchronous status update of a tool executing (status: `attempting`, `success`, `failure`). Includes `toolExecution` block with `toolCallId`, `name`, `status`, `target`, and `result`.
- `generationCompleted`: Sent when the turn is structurally complete. Includes the finalized `Message` object and token `responseMetadata`.
- `streamCompleted`: The very last event. Closes the connection.
- `error`: Indicates a failure. Includes an `error` string.

### Timeline Workspaces
- `GET /sessions/:id/workspaces` — List workspaces attached to timeline
- `POST /sessions/:id/workspaces` — Attach a workspace to timeline (body: `{ "workspaceId": "uuid" }`)
- `DELETE /sessions/:id/workspaces/:wsId` — Detach workspace from timeline
- `POST /sessions/:id/workspaces/:wsId/restore` — Re-attach a previously detached workspace

---

## Memories

### List Memories
`GET /memories`

**Query Parameters:**
- `page` (int)
- `perPage` (int)

### Create Memory
`POST /memories`

**Body:**
```json
{
  "title": "User Prefs",
  "content": "User likes dark mode",
  "tags": ["ui", "prefs"]
}
```

### Get Memory
`GET /memories/:id`

### Update Memory
`PATCH /memories/:id`

### Delete Memory
`DELETE /memories/:id`

### Search Memories
`POST /memories/search`

**Body:**
```json
{
  "query": "dark mode",
  "limit": 10
}
```

---

## Workspaces

- `GET /workspaces` — List all registered workspaces.
- `POST /workspaces` — Register a new workspace.
- `GET /workspaces/:id` — Get workspace details and tool list.
- `GET /workspaces/:workspaceId/files` — List files in workspace.
- `GET /workspaces/:workspaceId/files/:path` — Read a file.
- `PUT /workspaces/:workspaceId/files/:path` — Write a file.

---

## Agent Instances

Route prefix: `/api/agents`

Agent instances are the live runtime entities that attach to timelines and drive conversations.

### List Agent Instances
`GET /agents`

### Create Agent Instance
`POST /agents`

**Body:**
```json
{
  "name": "Research Agent",
  "description": "Specializes in searching and summarizing information.",
  "agentTemplateId": "uuid"
}
```
The `agentTemplateId` field is optional. If provided, the instance workspace is seeded from the AgentTemplate.

### Get Agent Instance
`GET /agents/:id`

### Update Agent Instance
`PATCH /agents/:id`

### Delete Agent Instance
`DELETE /agents/:id`

**Query Parameters:**
- `force` (bool, default: false): Force-detach from all timelines before deletion.

### Attach Agent to Timeline
`POST /agents/:id/attach/:timelineId`

Attaches the agent instance to a timeline. A timeline can have at most one attached agent. Idempotent if the same agent is already attached.

### Detach Agent from Timeline
`DELETE /agents/:id/attach/:timelineId`

### List Timelines for Agent
`GET /agents/:id/timelines`

Returns all timelines the agent is currently attached to.

---

## AgentTemplates

Route prefix: `/api/agentTemplates`

AgentTemplates are static templates used to seed new agent instance workspaces.

- `GET /agentTemplates` — List all AgentTemplate templates.
- `POST /agentTemplates` — Create a new AgentTemplate.
- `GET /agentTemplates/:id` — Get a specific AgentTemplate.
- `PATCH /agentTemplates/:id` — Update a template.
- `DELETE /agentTemplates/:id` — Delete a template.

---

## Jobs

- `GET /sessions/:id/...` — Job management scoped to a timeline session context.
- `GET /jobs` (global) — List all background jobs.
- `POST /jobs` — Create a new job.
  - Body: `{ "timelineId": "UUID", "title": "string", "agentInstanceId": "uuid" }`
- `GET /jobs/:id` — Get job status and logs.
- `DELETE /jobs/:id` — Delete a job.

---

## Clients

- `GET /clients` — List all registered clients.
- `DELETE /clients/:id` — Unregister a client.

---

## Configuration

- `GET /config` — Get current server configuration.
- `PATCH /config` — Update configuration (API keys, models).

---

## Tools

- `GET /tools` — List all available system tools.

---

## Prune

- `POST /prune/sessions` — Remove old or orphaned timeline data.

---

## SSE Chat Stream Summary

The `POST /sessions/{id}/chat/stream` endpoint emits Server-Sent Events:

| Event Type | Description |
| :--- | :--- |
| `generationContext` | Initial context for the turn (timeline, agent, primary workspace). |
| `thought` | Hidden CoT reasoning (inside `<think>` tags). |
| `delta` | Text fragments generated by the model. |
| `toolCall` | The model is requesting a tool. |
| `toolExecution` | Status of a tool execution (`attempting`, `success`, `failure`). |
| `generationCompleted` | Turn complete — includes full `Message` and token metadata. |
| `streamCompleted` | End of stream. |
| `error` | Error encountered during processing. |
