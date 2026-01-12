# Plan: Discord Integration and Signal Removal

## Phase 1: Cleanup and Removal of Signal [checkpoint: 4e0e71f]
Remove the legacy Signal PoC to prepare the codebase for the new architecture.

- [x] Task: Remove `Sources/MonadSignalBridge/` directory and `Sources/MonadCore/Services/gRPC/SignalBridgeEngine.swift`. 4e0e71f
- [x] Task: Update `Package.swift` and `project.yml` to remove the `MonadSignalBridge` target. 4e0e71f
- [x] Task: Write Tests: Ensure `MonadCore` and remaining targets still compile and run existing tests without Signal components. 4e0e71f
- [x] Task: Conductor - User Manual Verification 'Cleanup and Removal of Signal' (Protocol in workflow.md) 4e0e71f

## Phase 2: Discord Bridge Infrastructure
Set up the new target and the foundations for Discord communication.

- [ ] Task: Update `Package.swift` and `project.yml` to add the `DiscordBM` dependency and the `MonadDiscordBridge` target.
- [ ] Task: Implement Feature: Create the configuration loader supporting both Environment Variables and `discord_config.json`.
- [ ] Task: Implement Feature: Set up the basic `DiscordClient` and Gateway connection boilerplate using `DiscordBM`.
- [ ] Task: Write Tests: Verify configuration priority logic and the "Authorized User Only" filter.
- [ ] Task: Conductor - User Manual Verification 'Discord Bridge Infrastructure' (Protocol in workflow.md)

## Phase 3: Discord-to-gRPC Integration
Implement the core logic for routing messages and handling streaming responses.

- [ ] Task: Implement Feature: Message handler that maps incoming Discord DMs to gRPC `ChatStream` calls.
- [ ] Task: Implement Feature: Streaming logic to periodically edit the Discord message with received LLM deltas.
- [ ] Task: Implement Feature: Formatting logic to convert tool results and metadata into Discord Rich Embeds.
- [ ] Task: Write Tests: Functional tests for the bridge logic using mocked gRPC server responses and mock Discord events.
- [ ] Task: Conductor - User Manual Verification 'Discord-to-gRPC Integration' (Protocol in workflow.md)

## Phase 4: Reliability and UX Polish
Add final touches for a stable and responsive bot experience.

- [ ] Task: Implement Feature: Update Bot Activity/Status to show "Thinking..." or "Typing..." during generation.
- [ ] Task: Implement Feature: Graceful error handling for Discord Gateway reconnections and gRPC connection timeouts.
- [ ] Task: Write Tests: Stress test the streaming logic with large responses and simulated network errors.
- [ ] Task: Conductor - User Manual Verification 'Reliability and UX Polish' (Protocol in workflow.md)
