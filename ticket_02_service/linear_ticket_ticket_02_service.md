---
id: ticket_02_service
title: "Update LLM Service Layer & Protocols"
status: "Todo"
priority: "High"
order: 20
created: 2026-03-18
updated: 2026-03-18
links:
  - url: ../linear_ticket_parent.md
    title: Parent Ticket
---

# Description
Update `LLMServiceProtocol`, `LLMClientProtocol`, `LLMService`, and all clients (`OpenAIClient`, `OllamaClient`, `OpenRouterClient`). 
**CRITICAL**: Update `UnconfiguredLLMService` in `Sources/MonadCore/Dependencies/LLMDependencies.swift` to match the new protocol.
Pass all generation parameters down.
