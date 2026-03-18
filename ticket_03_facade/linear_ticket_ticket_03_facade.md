---
id: ticket_03_facade
title: "Update Facade and Chat Engine"
status: "Ready for Dev"
priority: "High"
order: 30
created: 2026-03-18
updated: 2026-03-18
links:
  - url: ../linear_ticket_parent.md
    title: Parent Ticket
  - url: ../2026-03-18-b4dabcf5/research_20260318.md
    title: Research Document
  - url: ./research_review.md
    title: Research Review
  - url: ../2026-03-18-b4dabcf5/plan_20260318.md
    title: Implementation Plan
  - url: ./plan_review.md
    title: Plan Review
---

# Description
Update `ChatTurnContext`, `ChatEngine`, and `MonadCore` to expose and propagate generation parameters.

## Research Findings
- `GenerationParameters` struct is already in `MonadShared`.
- `LLMService` protocol and implementation already support `GenerationParameters`.
- The propagation gap is in `ChatTurnContext`, `ChatEngine`, and `MonadCore`.
- `LLMStreamingStage` needs to be updated to pass these parameters to the service.
