# Specification: Discord Integration and Signal Removal

## Overview
This track involves replacing the existing Signal Proof-of-Concept (`MonadSignalBridge`) with a production-ready Discord bot (`MonadDiscordBridge`). The bot will allow a single authorized user to interact with the Monad Assistant via Direct Messages. It will leverage the `DiscordBM` library to provide a modern, reactive experience including streaming updates and rich formatting for tool outputs.

## Architecture
- **Client (Discord):** A standalone Swift executable (`MonadDiscordBridge`) that acts as a bridge between the Discord Gateway and the Monad gRPC server.
- **Protocol:** gRPC for communication with `MonadServer`.
- **Library:** `DiscordBM` for Discord API interaction.
- **Security:** Strict filtering to only respond to DMs from a specific, hardcoded User ID.

## Functional Requirements
### Removal of Signal
- Delete the `MonadSignalBridge` target and folder.
- Remove Signal-related dependencies and configurations from `Package.swift` and `project.yml`.
- Remove `SignalBridgeEngine.swift` from `MonadCore`.

### Discord Bot Implementation
- **Authentication:** Connect to Discord using a bot token provided via environment variable (`DISCORD_TOKEN`) or a local config file.
- **Authorization:** Only process messages from a hardcoded `DISCORD_USER_ID`. Ignore all other messages and servers.
- **Messaging:**
    - Listen for Direct Messages from the authorized user.
    - Forward queries to the Monad gRPC server.
    - **Streaming:** Update the Discord message in real-time as chunks are received from the server.
    - **Status:** Update bot activity to "Thinking..." or "Typing..." during generation.
    - **Rich Content:** Use Discord Embeds to display tool execution results (e.g., SQL results, file contents) and debug metadata.

## Non-Functional Requirements
- **Concurrency:** Fully utilize Swift 6 Structured Concurrency for event handling and gRPC streaming.
- **Stability:** Handle Discord Gateway reconnections and gRPC connection drops gracefully.
- **Configuration:** Priority-based config (Environment variables > Local config file).

## Acceptance Criteria
- [ ] `MonadSignalBridge` is completely removed from the codebase and build system.
- [ ] `MonadDiscordBridge` target is created and compiles.
- [ ] Bot successfully connects to Discord and appears online.
- [ ] Bot responds only to the authorized user's DMs.
- [ ] Responses are streamed (message edited periodically) to show progress.
- [ ] Tool results are formatted clearly using Discord Embeds.

## Out of Scope
- Support for multiple authorized users.
- Support for Discord Slash Commands (DMs only).
- Multi-server/Guild functionality.
