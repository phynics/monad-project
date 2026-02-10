import Foundation
import Logging
import OpenAI

/// An autonomous agent that executes jobs in the background
public actor AutonomousAgent {
    private let llmService: any LLMServiceProtocol
    private let persistenceService: any PersistenceServiceProtocol
    private let contextManager: ContextManager?
    private let logger = Logger(label: "com.monad.autonomous-agent")

    public init(
        llmService: any LLMServiceProtocol,
        persistenceService: any PersistenceServiceProtocol,
        contextManager: ContextManager? = nil
    ) {
        self.llmService = llmService
        self.persistenceService = persistenceService
        self.contextManager = contextManager
    }

    /// Execute a job within the context of a session
    public func execute(job: Job, session: ConversationSession, toolExecutor: ToolExecutor) async {
        logger.info("Starting execution of job: \(job.id) for session: \(session.id)")

        // 1. Update status to in_progress
        var currentJob = job
        if currentJob.status != .inProgress {
            currentJob.status = .inProgress
            currentJob.updatedAt = Date()
            try? await persistenceService.saveJob(currentJob)
        }

        // 2. Fetch History & Context
        guard (try? await persistenceService.fetchMessages(for: session.id)) != nil else {
            logger.error("Failed to fetch history for session: \(session.id)")
            await failJob(currentJob, reason: "Failed to load session history")
            return
        }

        // 3. Construct Initial Trigger Message
        let jobPrompt = """
            [BACKGROUND JOB EXECUTION]
            Job: \(job.title)
            Description: \(job.description ?? "N/A")
            Priority: \(job.priority)
            
            Please execute this job using available tools.
            When finished, state 'Job Complete'.
            """
        
        let triggerMessage = ConversationMessage(
            sessionId: session.id,
            role: .user,
            content: jobPrompt,
            timestamp: Date()
        )
        try? await persistenceService.saveMessage(triggerMessage)
        
        // 4. Run Execution Loop (ReAct / Tool Loop)
        // We simulate a chat loop where the agent responds to the job prompt + history.
        let maxTurns = 10
        var turnCount = 0
        var isComplete = false
        

        while turnCount < maxTurns && !isComplete {
            // Check for cancellation at start of turn (Critical for graceful shutdown)
            if Task.isCancelled {
                logger.info("Job execution cancelled via Task")
                await failJob(currentJob, reason: "Server Shutdown / Cancelled")
                return
            }

            turnCount += 1
            
            // Re-fetch history to get latest state (including own previous turns and tool outputs)
            // Ideally we'd optimize this, but let's be robust first.
            let latestHistory = (try? await persistenceService.fetchMessages(for: session.id))?.map { $0.toMessage() } ?? []
            
            // Get available tools from executor
            let availableTools = await toolExecutor.getAvailableTools()
            
            // Fetch Context from ContextManager (RAG)
            var contextNotes: [ContextFile] = []
            var contextMemories: [Memory] = []

            if let contextManager = contextManager {
                // Use last user message or job description as query
                let query = latestHistory.last(where: { $0.role == .user })?.content ?? job.description ?? job.title
                
                do {
                    let contextData = try await contextManager.gatherContext(
                        for: query,
                        history: latestHistory,
                        limit: 5
                    )
                    contextNotes = contextData.notes
                    // Convert SemanticSearchResult to Memory
                    contextMemories = contextData.memories.map { $0.memory }
                } catch {
                    logger.warning("Failed to gather context for job: \(error)")
                }
            }

            let (messages, _, _) = await llmService.buildPrompt(
                userQuery: "Continue execution",
                contextNotes: contextNotes,
                memories: contextMemories,
                chatHistory: latestHistory, 
                tools: availableTools,
                systemInstructions: "You are an autonomous agent executing a background job. Complete the task."
            )
            
            // Execute LLM Step (Stream/Generate)
            // We use `chatStream` but consume it entirely to get the full response + tool calls.
            
            var assistantContent = ""
            var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
            
            do {
                let stream = await llmService.chatStream(
                  messages: messages,
                  tools: availableTools.map { $0.toToolParam() },
                  responseFormat: nil
                )
                
                for try await result in stream {
                    // Check for cancellation during stream
                    if Task.isCancelled {
                        throw CancellationError()
                    }

                    if let content = result.choices.first?.delta.content {
                        assistantContent += content
                    }
                    
                    if let calls = result.choices.first?.delta.toolCalls {
                        for call in calls {
                            guard let index = call.index else { continue }
                            var acc = toolCallAccumulators[index] ?? ("", "", "")
                            if let id = call.id { acc.id = id }
                            if let name = call.function?.name { acc.name += name }
                            if let args = call.function?.arguments { acc.args += args }
                            toolCallAccumulators[index] = acc
                        }
                    }
                }
                
                // Process Result
                // 1. Convert accumulated tool calls to MonadCore.ToolCall for storage
                var toolCalls: [MonadCore.ToolCall] = []
                
                if !toolCallAccumulators.isEmpty {
                    toolCalls = toolCallAccumulators.sorted(by: { $0.key < $1.key }).compactMap { _, value in
                        guard !value.name.isEmpty else { return nil }
                        let argsData = value.args.data(using: .utf8) ?? Data()
                        let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                        return MonadCore.ToolCall(name: value.name, arguments: args)
                    }
                } else if let fallback = ToolOutputParser.parse(from: assistantContent) {
                    logger.info("Detected fallback tool call in Agent content: \(fallback.name)")
                    toolCalls = [MonadCore.ToolCall(name: fallback.name, arguments: fallback.arguments)]
                }
                
                let toolCallsJSON = (try? SerializationUtils.jsonEncoder.encode(toolCalls)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

                let assistantMsg = ConversationMessage(
                    sessionId: session.id,
                    role: .assistant,
                    content: assistantContent,
                    timestamp: Date(),
                    toolCalls: toolCallsJSON
                )
                try await persistenceService.saveMessage(assistantMsg)
                
                // 2. Execute Tools (if any)
                if !toolCalls.isEmpty {
                    for toolCall in toolCalls {
                        // Check cancellation before tool execution
                        if Task.isCancelled {
                           throw CancellationError()
                        }

                        let result: String
                        
                        // Find matching tool
                        if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                            do {
                                let args = toolCall.arguments.mapValues { $0.value }
                                let toolResult = try await tool.execute(parameters: args)
                                result = toolResult.output
                            } catch {
                                result = "Error: \(error.localizedDescription)"
                            }
                        } else {
                            result = "Error: Tool '\(toolCall.name)' not found"
                        }
                        
                        // 3. Save Tool Result Message
                        // Tool messages need toolCallId (String) in ConversationMessage
                        let toolMsg = ConversationMessage(
                            sessionId: session.id,
                            role: .tool,
                            content: result,
                            timestamp: Date(),
                            toolCallId: toolCall.id.uuidString // toolCall.id is UUID in MonadCore
                        )
                        try await persistenceService.saveMessage(toolMsg)
                        
                        // Check for graceful failure triggers in result
                        if result.contains("Client not connected") || result.contains("Workspace not found") {
                            logger.warning("Job paused/failed due to missing client/workspace.")
                            await failJob(currentJob, reason: "Missing Client/Workspace: " + result)
                            return
                        }
                    }
                } else {
                    // No tool calls -> Likely completion or question.
                    if assistantContent.lowercased().contains("job complete") {
                        isComplete = true
                    } else if assistantContent.lowercased().contains("i need more information") {
                         isComplete = true 
                    }
                }
                
            } catch is CancellationError {
                logger.info("LLM Execution cancelled")
                await failJob(currentJob, reason: "Server Shutdown / Cancelled")
                return
            } catch {
                logger.error("LLM Execution Failed: \(error)")
                await failJob(currentJob, reason: "LLM Error: \(error.localizedDescription)")
                return
            }
        }

        // 5. Completion
        currentJob.status = .completed
        currentJob.updatedAt = Date()
        try? await persistenceService.saveJob(currentJob)
        logger.info("Job \(currentJob.id) completed")
    }
    
    private func failJob(_ job: Job, reason: String) async {
        var failedJob = job
        failedJob.status = .failed
        failedJob.updatedAt = Date()
        try? await persistenceService.saveJob(failedJob)
        logger.error("Job \(job.id) failed: \(reason)")
        
        // Also log failure to chat
        let msg = ConversationMessage(
            sessionId: job.sessionId,
            role: .system,
            content: "Job Failed: \(reason)",
            timestamp: Date()
        )
        try? await persistenceService.saveMessage(msg)
    }
}
