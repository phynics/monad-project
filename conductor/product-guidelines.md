# Product Guidelines

## Tone and Voice
- **Technical & Precise**: We use accurate terminology (e.g., "semantic retrieval," "vector embeddings," "modular architecture"). Clarity and efficiency are prioritized.
- **Helpful & Approachable**: While technical, we remain guiding. Complex architectural decisions are explained with clear rationales.

## Design Principles
- **Local-First**: Performance and privacy are paramount. Operations should favor local execution and data persistence (SQLite/GRDB) where possible.
- **Modularity**: Components (Core, Server, CLI) must remain decoupled to allow for independent extension and testing.
- **Context-Centric**: Every feature should be evaluated based on how it enhances or utilizes the user's context.

## Documentation Standards
- **Prose Style**: Use active voice and concise sentences.
- **Code Examples**: All documentation must include runnable Swift snippets where applicable.
- **Transparency**: Document the "why" behind the architecture, not just the "how."
