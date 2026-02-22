# Monad Context System

This document explains how Monad gathers, filters, and assembles context for the Large Language Model (LLM). 

## 1. Context Assembly Pipeline

The `ChatEngine` orchestrates the context gathering process before every LLM turn. It uses the `ContextBuilder` DSL from the `MonadPrompt` module.

### Components of a Prompt
1. **System Instructions**: The base persona and behavioral rules (from `DefaultInstructions.swift`).
2. **Context Notes**: Files retrieved from the `Notes/` directory in the Primary Workspace.
3. **Memories**: Relevant long-term facts retrieved via semantic search from the local vector store.
4. **Tools**: Definitions of available capabilities, formatted with workspace provenance.
5. **Chat History**: Recent messages from the current session (automatically truncated to fit budget).
6. **User Query**: The current user input.

---

## 2. Context Notes (`Notes/` Directory)

Monad uses a filesystem-based approach for long-term project context and persona storage.

- **Location**: Every session has a `Notes/` directory in its Primary Workspace.
- **Seeding**: New sessions are initialized with `Welcome.md` and `Project.md`.
- **RAG**: The `ContextManager` reads these files and provides them to the prompt.
- **AI Modification**: The LLM is instructed to proactively update these files using `write_to_file` to store important state or refined instructions.

---

## 3. The Agent Model

Agents provide high-level "profiles" that influence the prompt:
- **System Prompt**: Base behavior.
- **Persona Prompt**: Specific character traits.
- **Guardrails**: Safety and formatting constraints.

The `AgentRegistry` and `PersistenceService` seed default agents like the **Default Assistant** and **Agent Coordinator**.

---

## 4. Prompt Engineering DSL (`MonadPrompt`)

Prompts are built using a type-safe `@ContextBuilder` result builder:

```swift
let prompt = await ContextBuilder {
    SystemInstructions(DefaultInstructions.system)
    ContextNotes(notes).priority(100)
    Memories(memories).priority(85).strategy(.summarize)
    Tools(tools).priority(80)
    ChatHistory(history).priority(70).strategy(.truncate(tail: false))
    UserQuery(query).priority(10)
}
```

### Token Budgeting
The `TokenBudget` system ensures the generated prompt fits within the model's context window:
- **Priority**: Higher priority sections (like Notes) are allocated tokens first.
- **Compression Strategies**:
  - `keep`: Do not compress; drop if no budget.
  - `truncate`: Clip the text from the start or end.
  - `summarize`: Use a smaller LLM turn to produce a gist of the content.

---

## 5. Workspace & Tool Relationship

Tools are surfaced to the LLM with **provenance info** to help it reason about its environment.

### Tool Types
- **System Tools**: Global capabilities (e.g., `memory_search`, `web_search`).
- **Workspace Tools**: Specific to a project directory or remote client.
- **Session Tools**: Ephemeral tools scoped to the current conversation.

### Path Resolution
The LLM is instructed on how to handle paths across workspaces:
- Paths in the **Primary Workspace** are typically relative to the session root.
- Paths in **Attached Workspaces** must be resolved relative to their respective indices or URIs.
- Client-side tools (like `edit_file` in a local IDE) only execute when the corresponding `RemoteWorkspace` is healthy.
