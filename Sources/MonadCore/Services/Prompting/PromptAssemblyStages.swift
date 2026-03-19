import Foundation
import MonadPrompt
import MonadShared

// MARK: - Standard Assembly Stages

/// Appends system instructions to the prompt.
public struct SystemInstructionsStage: PromptAssemblyStage {
    public init() {}
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
    public init() {}
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
    public init() {}
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let notes = context.request.contextNotes
            await context.append(ContextNotes(notes))
        }
    }
}

/// Appends memories to the prompt.
public struct MemoriesStage: PromptAssemblyStage {
    public init() {}
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let memories = context.request.memories
            await context.append(Memories(memories))
        }
    }
}

/// Appends tools to the prompt.
public struct ToolsStage: PromptAssemblyStage {
    public init() {}
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let tools = context.request.tools
            await context.append(Tools(tools))
        }
    }
}

/// Appends workspace and client context to the prompt.
public struct WorkspacesContextStage: PromptAssemblyStage {
    public init() {}
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
    public init() {}
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
    public init() {}
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
    public init() {}
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let query = context.request.userQuery
            await context.append(UserQuery(query))
        }
    }
}

/// Appends extension sections provided in the request context.
public struct ExtensionSectionsStage: PromptAssemblyStage {
    public init() {}
    public func process(_ context: PromptAssemblyContext) async throws -> AsyncThrowingStream<PromptAssemblyEvent, Error> {
        try await running(context) {
            let sections = context.extensionSections
            await context.append(sections)
        }
    }
}
