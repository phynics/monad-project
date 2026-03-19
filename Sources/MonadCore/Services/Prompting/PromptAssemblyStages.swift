import Foundation
import MonadPrompt
import MonadShared

// MARK: - Standard Assembly Stages

/// Appends system instructions to the prompt.
public struct SystemInstructionsStage: PromptAssemblyStage {
    /// Initializes a new system instructions stage.
    public init() {}
    /// Appends system instructions from the request or default instructions to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let request = context.request
            let instructions = request.systemInstructions ?? DefaultInstructions.system()
            await context.append(SystemInstructions(instructions))
        }
    }
}

/// Appends agent context and timeline title to the prompt.
public struct AgentContextStage: PromptAssemblyStage {
    /// Initializes a new agent context stage.
    public init() {}
    /// Appends agent instance and timeline title information to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            if let agent = context.agentInstance {
                let timelineTitle = context.timeline?.title
                await context.append(AgentContext(agent, timelineTitle: timelineTitle))
            }
        }
    }
}

/// Appends context notes to the prompt.
public struct ContextNotesStage: PromptAssemblyStage {
    /// Initializes a new context notes stage.
    public init() {}
    /// Appends discovered notes from the request to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let notes = context.request.contextNotes
            await context.append(ContextNotes(notes))
        }
    }
}

/// Appends memories to the prompt.
public struct MemoriesStage: PromptAssemblyStage {
    /// Initializes a new memories stage.
    public init() {}
    /// Appends retrieved memories from the request to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let memories = context.request.memories
            await context.append(Memories(memories))
        }
    }
}

/// Appends tools to the prompt.
public struct ToolsStage: PromptAssemblyStage {
    /// Initializes a new tools stage.
    public init() {}
    /// Appends available tools from the request to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let tools = context.request.tools
            await context.append(Tools(tools))
        }
    }
}

/// Appends workspace and client context to the prompt.
public struct WorkspacesContextStage: PromptAssemblyStage {
    /// Initializes a new workspaces context stage.
    public init() {}
    /// Appends workspace and client information to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let request = context.request
            await context.append(WorkspacesContext(
                workspaces: request.workspaces,
                primaryWorkspace: request.primaryWorkspace,
                clientName: request.clientName
            ))
        }
    }
}

/// Appends timeline context to the prompt.
public struct TimelineContextStage: PromptAssemblyStage {
    /// Initializes a new timeline context stage.
    public init() {}
    /// Appends timeline information to the context if available.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            if let timeline = context.timeline {
                await context.append(TimelineContext(timeline))
            }
        }
    }
}

/// Appends optimized chat history to the prompt.
public struct ChatHistoryStage: PromptAssemblyStage {
    /// Initializes a new chat history stage.
    public init() {}
    /// Optimizes and appends conversation history to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let history = context.request.chatHistory
            let optimized = PromptBuilder.optimizeHistory(
                history,
                availableTokens: PromptBuilder.maxHistoryTokens - PromptBuilder.historyTokenBuffer
            )
            await context.append(ChatHistory(optimized))
        }
    }
}

/// Appends the user's latest query to the prompt.
public struct UserQueryStage: PromptAssemblyStage {
    /// Initializes a new user query stage.
    public init() {}
    /// Appends the latest user query to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let query = context.request.userQuery
            await context.append(UserQuery(query))
        }
    }
}

/// Appends extension sections provided in the request context.
public struct ExtensionSectionsStage: PromptAssemblyStage {
    /// Initializes a new extension sections stage.
    public init() {}
    /// Appends any additional sections provided by extensions to the context.
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let sections = context.extensionSections
            await context.append(sections)
        }
    }
}
