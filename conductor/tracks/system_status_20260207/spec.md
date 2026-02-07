# Track Specification: Implement System Status & Health Check

## Overview
This track focuses on implementing a robust health check mechanism for `MonadServer` and exposing it via a CLI command in `MonadCLI`. This ensures that users can verify the connectivity and readiness of the core system components (Database, AI Provider, etc.) before performing complex operations.

## Goals
- **Server Endpoint:** Create a `/health` or `/status` endpoint in `MonadServer` that returns the status of critical subsystems.
- **Subsystem Checks:**
    - **Database:** Verify connection to SQLite/GRDB.
    - **AI Provider:** Check configuration validity (e.g., API key presence) or perform a lightweight connectivity check.
    - **Memory/System:** Report basic system stats (uptime, version).
- **CLI Command:** Implement `monad status` (or similar) in `MonadCLI` to consume this endpoint and display a formatted status report.
- **Resilience:** Ensure the check is lightweight and non-blocking.

## Requirements
- **Endpoint:** `GET /status` returning a JSON object with component statuses.
- **JSON Structure:**
  ```json
  {
    "status": "ok", // or "degraded", "down"
    "version": "1.0.0",
    "uptime": 12345,
    "components": {
      "database": { "status": "ok" },
      "ai_provider": { "status": "ok", "provider": "openai" }
    }
  }
  ```
- **CLI Output:** A table or list view showing the status of each component with color-coded indicators (Green/Red).

## Non-Functional Requirements
- **Latency:** The status check should return in < 500ms.
- **Security:** Publicly accessible (or basic auth if preferred, but usually open for localhost tools).
