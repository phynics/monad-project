# Workspaces & Tool Execution

## Motivation
Current LLM tool implementations lack persistent state and context awareness, treating file operations and command execution as isolated, ephemeral events. The Workspaces feature addresses this by establishing secure, addressable execution boundaries. This allows Monad to maintain persistent file storage on the server, safely access a user's local development environment, and isolate sensitive operations in sandboxed containers, all while using a unified addressing scheme.

## Key Concepts

### 1. The Universal Address (URI)
We use an SCP-like URI scheme to uniquely identify workspaces across the distributed system.

| URI Example | Type | Description |
| :--- | :--- | :--- |
| `monad-server:/sessions/a1b2` | **Server** | A persistent workspace for a specific conversation. |
| `macbook-pro:~/dev/monad` | **Client** | A developer's local project folder. |
| `git:github.com/monad/core` | **Virtual** | A transient workspace cloned from a repository. |

### 2. Session Architecture
Every conversation session is assigned a **Primary Workspace** on the server for long-term memory and state. Users can **Attach** additional workspaces (like local folders) to bring them into the context.

```mermaid
graph TD
    User((User)) -->|Interacts with| Session[Session Controller]
    
    subgraph "Server"
        Session --> Primary[Primary Workspace]
    end

    subgraph "Client (Local)"
        Attached1["Attached Workspace\nmacbook:~/dev/project"]
    end

    Session -.->|Attaches| Attached1
```

## Workflows

### 1. Remote Tool Execution (Client-Side)
This workflow demonstrates how the Server orchestrates tools running on the Client's machine (e.g., editing a local file).

```mermaid
sequenceDiagram
    participant CLI as MonadCLI (Client)
    participant Server as MonadServer
    participant LLM as LLM Service
    participant FS as Local Filesystem

    Note over CLI: User attaches workspace\n"macbook:~/project"
    
    CLI->>Server: "Refactor main.swift"
    Server->>LLM: Generate Response
    
    Note over LLM: Decides to edit file in\n"macbook:~/project"
    
    LLM->>Server: Tool Call: write_file(path="main.swift", ...)
    
    Server->>Server: Resolve Workspace URI
    Note right of Server: Target is Client-owned
    
    Server->>CLI: Request Tool Execution (JSON)
    
    CLI->>CLI: Verify Permission
    CLI->>FS: Write File
    FS-->>CLI: Success
    
    CLI-->>Server: Execution Result
    Server->>LLM: Result Context
    LLM-->>Server: Final Response
    Server-->>CLI: "Refactoring complete."
```

### 2. Intelligent Tool Resolution Strategy
When the LLM requests a tool without a specific target, the system routes the request based on priority.

```mermaid
flowchart TD
    Request[Tool Call Generated] --> CheckID{Workspace ID Defined?}
    
    CheckID -- Yes --> Target[Target Workspace]
    
    CheckID -- No --> CheckPrimary{Tool in Primary?}
    
    CheckPrimary -- Yes --> Primary["Primary Workspace (Server)"]
    
    CheckPrimary -- No --> CheckAttached{Tool in Attached?}
    
    CheckAttached -- Yes --> FirstAttached["Attached Workspace (Client/Other)"]
    
    CheckAttached -- No --> Error[Error: Tool Not Found]
    
    Target --> Execute((Execute))
    Primary --> Execute
    FirstAttached --> Execute
```

## Security & Isolation

*   **Boundaries**: Tools are strictly confined to their workspace `rootPath`. Path traversal attempts are blocked at the framework level.
*   **Trust Levels**: Workspaces are assigned levels (`Full` or `Restricted`). 
    *   **Full**: Trusted environments where tools execute without per-call interruption.
    *   **Restricted**: Local directories and untrusted environments (e.g., cloned git repos). These require explicit user approval for tool execution and operate with a limited toolset.
*   **Locks**: Workspaces are locked during generation cycles to ensure state consistency between the user and the AI.