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

## Sessions

### List Sessions
`GET /sessions`

**Query Parameters:**
- `page` (int, default: 1)
- `perPage` (int, default: 20)
- `archived` (bool, optional): Filter by archived status.

### Create Session
`POST /sessions`

**Body:**
```json
{
  "title": "Project Planning",
  "persona": "architect.md",
  "primaryWorkspaceId": "uuid"
}
```

### Get Session
`GET /sessions/:id`

### Update Session
`PATCH /sessions/:id`

**Body:**
```json
{
  "title": "New Title",
  "persona": "coder.md" 
}
```

### Delete Session
`DELETE /sessions/:id`

### Get Session Messages
`GET /sessions/:id/messages`

**Query Parameters:**
- `page` (int, default: 1)
- `perPage` (int, default: 50)

### Chat (Stream)
`POST /sessions/:id/chat/stream`

**Headers:**
- `Accept: text/event-stream`

**Body:**
```json
{
  "message": "Hello",
  "toolOutputs": [...] 
}
```
**Response:** Server-Sent Events (SSE) stream of `ChatDelta` objects.

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

### List Workspaces
`GET /workspaces`

### Create Workspace
`POST /workspaces`

### Get Workspace
`GET /workspaces/:id`

### Update Workspace
`PATCH /workspaces/:id`

### Delete Workspace
`DELETE /workspaces/:id`

---

## Tools

### List System Tools
`GET /tools`

### List Session Tools
`GET /session/:sessionId` (Note: Endpoint path refined to avoid collision with `/tools/:id` if that ever existed)

---
