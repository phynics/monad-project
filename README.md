# Monad Assistant

Monad Assistant is a fast, native AI app for macOS and iOS. It's written in **Swift 6.0** and **SwiftUI** to run smoothly on your Apple devices.

The goal is simple: Help Large Language Models (LLMs) understand your personal data. It does this by finding the right notes, documents, and memories, and giving them to the AI exactly when it needs them.

## Core Concepts

### 🧠 Finding the Right Info
The AI is only as good as the information you give it. Monad makes sure the AI has what it needs.

- **Smart Search**: It scans your memories and notes to find things related to your current question.
- **Better Tagging**: It uses a small AI model to tag your input, helping it find relevant info even if you don't use the exact right keywords.
- **Thinking Models**: It works great with models like DeepSeek R1 that "think" and plan before they answer.

### 门 Real Tools
The AI isn't stuck in the chat box. It can actually do things.

- **Standard Tools**: It uses a standard way to talk to tools, so adding new abilities (like checking files or browsing the web) is easy.
- **Trying Again**: If the AI tries to read a file and fails, it doesn't just give up. It can look at the directory listing, find the correct filename, and try again—just like a human would.

### 💾 Database Access
Monad lets the AI talk directly to the database.

- **Writing SQL**: The AI can write SQL queries to create new tables, organize data, or find complex patterns in your info.
- **Safety First**: The AI can play with its own data, but your core chat history is locked down so it can't accidentally delete your memories.

### 📄 Working with Files
Documents are more than just attachments.

- **Your Workspace**: You can pin the files you are currently working on. This tells the AI, "Pay attention to these."
- **Active Reading**: The AI can search inside your files, read specific parts, or summarize them for you.

### 🛠️ How it's Built
We split the app into two main parts to keep it clean and fast.

- **The Brain (MonadCore)**: This handles all the logic, the database, and the tools. It can run on macOS, Linux, or in Docker.
- **The Connection (gRPC)**: The Brain talks to the App using gRPC, which is a super fast way for programs to communicate.
- **The Dashboard**: We track how fast the AI is generating text and how long tasks take, so you can see real-time performance stats.

## Project Structure

- **MonadCore**: The shared brain (Logic, DB, Tools).
- **MonadServerCore**: Server-specific wrappers and the gRPC handler implementations.
- **MonadUI**: Shared SwiftUI components for macOS and iOS.
- **MonadTestSupport**: Mocks and utilities for the test suite.

## Getting Started

1. **Generate Project**:
   ```bash
   make generate
   ```
2. **Dependencies**:
   ```bash
   make install-deps
   ```
3. **Build & Run**:
   ```bash
   make build
   make run
   ```

## License
MIT License. See [LICENSE](LICENSE) for details.
