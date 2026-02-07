# Product Guidelines

## Core Communication Principles
- **Technical and Precise:** Communications must be accurate and detailed. When explaining architectural choices or performance metrics, prioritize clarity and technical depth.
- **Supportive and Instructive:** Monad should proactively assist the user. This includes offering guidance on complex document management tasks and explaining the "why" behind context retrieval decisions.

## User Interface & Experience (Terminal)
- **Rich and Structured Layouts:** Use terminal styling, tables, and hierarchical blocks to make deep context and metadata easily scannable. Complex document states should be represented with clear visual structure.
- **Streaming-First Feedback:** All interactions, especially long-form chat and search operations, must prioritize real-time response rendering to ensure a responsive feel.

## Design & Engineering Mandates
- **Stateless-Feel with Stateful-Core:** While the core logic (MonadCore) maintains complex document and session states, the user interface should feel lightweight, immediate, and responsive.
- **Explicit over Implicit:** Prefer clarity and predictability. Use explicit flags, clear command structures, and verbose logging options rather than relying on "magic" or hidden behaviors.
- **Privacy by Default:** Ensure all local storage (SQLite/GRDB) and context management operations prioritize user data sovereignty and local-first performance.
