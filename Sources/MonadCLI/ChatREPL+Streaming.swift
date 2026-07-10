import Foundation
import MonadClient
import MonadShared
import PKShared

// Needed for fflush
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

extension ChatREPL {
    func sendMessage(_ initialMessage: String) async {
        if !lastServerStatus {
            TerminalUI.printError("Server is offline. Check connection and try again.")
            return
        }

        let timelineId = timeline.id
        guard await synchronizeAgentStateBeforeSend(timelineId: timelineId) else {
            return
        }

        startEscapeMonitor()
        currentGenerationTask = Task {
            var currentMessage = initialMessage
            var currentToolOutputs: [ToolOutputSubmission]?
            var keepGoing = true

            while keepGoing && !Task.isCancelled {
                keepGoing = false
                do {
                    if currentMessage != "" || currentToolOutputs == nil {
                        print("") // Only print new line if it's the start of a turn
                    }

                    let stream = try await client.chat.execute(
                        timelineId: timelineId,
                        message: currentMessage,
                        toolOutputs: currentToolOutputs
                    )

                    var streamState = StreamState()

                    for try await event in stream {
                        if Task.isCancelled { break }
                        handleStreamEvent(event, state: &streamState)
                    }

                    emitToolCallingDiagnosticIfNeeded(streamState)

                    if !streamState.pendingToolCalls.isEmpty && !Task.isCancelled {
                        let submissions = await executeLocalToolCalls(
                            streamState.pendingToolCalls,
                            toolCallArgs: streamState.toolCallArgs,
                            timelineId: timelineId
                        )
                        guard let toolOutputs = submissions else { break }

                        currentMessage = ""
                        currentToolOutputs = toolOutputs
                        keepGoing = true
                    }

                } catch {
                    if !(error is CancellationError) {
                        print("")
                        await handleError(error)
                    }
                }
            } // END WHILE
        }
        await currentGenerationTask?.value
        currentGenerationTask = nil
        stopEscapeMonitor()
    }

    private func synchronizeAgentStateBeforeSend(timelineId: UUID) async -> Bool {
        do {
            let timeline = try await client.chat.getTimeline(id: timelineId)
            let decision = ChatSendPreflight.evaluate(
                serverAttachedAgentId: timeline.attachedAgentInstanceId,
                localAgentId: currentAgent?.id
            )

            switch decision {
            case .proceed:
                return true
            case let .syncLocalAgent(agentId):
                let agent = try await client.chat.getAgentInstance(id: agentId)
                await setAgent(agent)
                return true
            case .abortNoAttachedAgent:
                if currentAgent != nil {
                    await setAgent(nil)
                }
                TerminalUI.printError(
                    "No agent attached to this timeline. Use /agent attach or /agent create before chatting."
                )
                return false
            }
        } catch {
            await handleError(error)
            return false
        }
    }

    // MARK: - Stream State

    private struct StreamState {
        var assistantStartPrinted = false
        var sawGenerationContent = false
        var sawGenerationCompleted = false
        var sawToolCallDelta = false
        var sawToolExecutionEvent = false
        var toolCallArgs: [String: String] = [:]
        var toolCallNames: [Int: String] = [:]
        var pendingToolCalls: [ToolCall] = []
    }

    // MARK: - Event Handling

    private func handleStreamEvent(_ event: ChatEvent, state: inout StreamState) {
        switch event {
        case let .meta(meta):
            handleMetaEvent(meta)
        case let .delta(delta):
            handleDeltaEvent(delta, state: &state)
        case let .error(err):
            handleErrorEvent(err)
        case let .completion(completion):
            handleCompletionEvent(completion, state: &state)
        }
    }

    private func handleMetaEvent(_ meta: ChatEvent.MetaEvent) {
        switch meta {
        case let .generationContext(metadata):
            if !metadata.memories.isEmpty || !metadata.files.isEmpty {
                let memories = metadata.memories.count
                let files = metadata.files.count
                print(TerminalUI.dim("Using \(memories) memories and \(files) files"))
            }
        case .generationCompleted:
            break
        }
    }

    private func handleDeltaEvent(_ delta: ChatEvent.DeltaEvent, state: inout StreamState) {
        switch delta {
        case let .reasoning(thought):
            if !state.assistantStartPrinted {
                print(TerminalUI.dim("🤔 Thinking..."))
                state.assistantStartPrinted = true
            }
            print(TerminalUI.dim(thought), terminator: "")
            fflush(stdout)

        case let .generation(content):
            if !state.assistantStartPrinted {
                TerminalUI.printAssistantStart()
                state.assistantStartPrinted = true
            }
            state.sawGenerationContent = true
            print(content, terminator: "")
            fflush(stdout)

        case let .toolCall(delta):
            state.sawToolCallDelta = true
            if let callId = delta.id {
                state.toolCallArgs[callId] = (state.toolCallArgs[callId] ?? "") + (delta.arguments ?? "")
            }
            if let name = delta.name {
                state.toolCallNames[delta.index] = (state.toolCallNames[delta.index] ?? "") + name
            }

        case let .toolExecution(toolCallId, status):
            state.sawToolExecutionEvent = true
            handleToolExecutionDelta(toolCallId: toolCallId, status: status, state: &state)

        case .sidecar:
            // Sidecar directives (title/summary/etc.) have no CLI presentation yet; the
            // concrete directives and their routing are Yakamoz-side (SID-1/SID-2).
            break
        }
    }

    private func handleToolExecutionDelta(
        toolCallId: String,
        status: ToolExecutionStatus,
        state: inout StreamState
    ) {
        switch status {
        case let .attempting(name, ref):
            if state.assistantStartPrinted { print("") }
            state.assistantStartPrinted = false
            let args = state.toolCallArgs[toolCallId] ?? ""
            printToolAttempt(name: name, argsJSON: args, reference: ref)
        default:
            break
        }
    }

    private func handleErrorEvent(_ err: ChatEvent.ErrorEvent) {
        switch err {
        case let .toolCallError(_, name, error):
            print(TerminalUI.red("  ✗ Tool Error (\(name)): \(error)"))
        case let .error(message, identity):
            print("\n")
            if let identity = identity {
                TerminalUI.printError("Stream Error [\(identity.domain):\(identity.code)]: \(message)")
            } else {
                TerminalUI.printError("Stream Error: \(message)")
            }
        case .generationCancelled:
            print(TerminalUI.yellow("\n[Generation cancelled]"))
        }
    }

    private func handleCompletionEvent(_ completion: ChatEvent.CompletionEvent, state: inout StreamState) {
        switch completion {
        case let .generationCompleted(msg, meta):
            handleGenerationCompleted(message: msg, metadata: meta, state: &state)
        case let .completedEmpty(finishReason):
            state.sawGenerationCompleted = true
            let reason = finishReason.map { " (\($0))" } ?? ""
            print(TerminalUI.dim("\n[Model produced an empty response\(reason)]"))
        case let .toolExecution(_, status):
            handleToolExecutionCompletion(status: status)
        case .streamCompleted:
            break
        case .sidecarsCompleted:
            // No CLI presentation yet; see the note in handleDeltaEvent's .sidecar case.
            break
        }
    }

    private func handleGenerationCompleted(
        message: Message,
        metadata: APIResponseMetadata,
        state: inout StreamState
    ) {
        state.sawGenerationCompleted = true
        if let snapshotData = metadata.turnSnapshotData {
            updateTurnSnapshot(snapshotData)
        }
        let tokens = metadata.totalTokens ?? 0
        let dur = String(format: "%.1fs", metadata.duration ?? 0)
        print(TerminalUI.dim("\n[Generated in \(dur), \(tokens) tokens]"))

        if let calls = message.toolCalls, !calls.isEmpty {
            state.pendingToolCalls = calls
        }
    }

    private func emitToolCallingDiagnosticIfNeeded(_ state: StreamState) {
        let diagnosticState = ToolCallingDiagnostics.State(
            assistantStarted: state.assistantStartPrinted,
            sawGenerationContent: state.sawGenerationContent,
            sawGenerationCompleted: state.sawGenerationCompleted,
            sawToolCallDelta: state.sawToolCallDelta,
            sawToolExecutionEvent: state.sawToolExecutionEvent,
            streamedToolCallNames: state.toolCallNames
                .sorted(by: { $0.key < $1.key })
                .map(\.value)
                .filter { !$0.isEmpty }
        )

        guard let message = ToolCallingDiagnostics.message(for: diagnosticState) else {
            return
        }

        print("")
        TerminalUI.printWarning(message)
        logger.warning("\(message)")
    }

    private func handleToolExecutionCompletion(status: ToolExecutionStatus) {
        switch status {
        case let .success(result):
            printToolResult(result.output)
        case let .failed(_, error):
            print(TerminalUI.red("  ✗ \(error)"))
        case let .executionError(error):
            print(TerminalUI.red("  ✗ \(error)"))
        default:
            break
        }
    }

    // MARK: - Local Tool Execution

    private func executeLocalToolCalls(
        _ pendingToolCalls: [ToolCall],
        toolCallArgs: [String: String],
        timelineId: UUID
    ) async -> [ToolOutputSubmission]? {
        print("") // Spacing for local tools

        guard let wsId = await resolveToolWorkspace(timelineId: timelineId) else {
            return nil
        }

        let workspace: WorkspaceReference
        do {
            workspace = try await client.workspace.getWorkspace(wsId)
        } catch {
            logger.error("Failed to get workspace \(wsId): \(error)")
            print(TerminalUI.red("  ✗ Cannot execute local tools: could not fetch workspace details."))
            return nil
        }

        printLocalToolAttempts(pendingToolCalls, toolCallArgs: toolCallArgs)

        let executor = ClientToolExecutor(client: client, timeline: timeline, repl: self)
        let submissions = await executor.execute(toolCalls: pendingToolCalls, in: workspace)

        printLocalToolResults(submissions)

        return submissions
    }

    private func resolveToolWorkspace(timelineId: UUID) async -> UUID? {
        var targetWsId: UUID?
        do {
            let timelineWS = try await client.workspace.listTimelineWorkspaces(timelineId: timelineId)
            targetWsId = selectedWorkspaceId ?? timelineWS.primary?.id ?? timelineWS.attached.first?.id
        } catch {
            logger.error("Failed to list timeline workspaces: \(error)")
        }

        guard let wsId = targetWsId else {
            logger.error("No active workspace found to execute local tools.")
            print(TerminalUI.red("  ✗ Cannot execute local tools: no active workspace found."))
            return nil
        }
        return wsId
    }

    private func printLocalToolAttempts(_ toolCalls: [ToolCall], toolCallArgs _: [String: String]) {
        for call in toolCalls {
            let arguments: String
            do {
                let data = try SerializationUtils.jsonEncoder.encode(call.arguments)
                arguments = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                logger.error("Failed to encode tool call arguments: \(error)")
                arguments = "{}"
            }
            printToolAttempt(name: call.name, argsJSON: arguments, reference: nil)
        }
    }

    private func printLocalToolResults(_ submissions: [ToolOutputSubmission]) {
        for submission in submissions {
            if submission.output.hasPrefix("Error:") {
                print(TerminalUI.red("  ✗ \(submission.output)"))
            } else {
                printToolResult(submission.output)
            }
        }
    }
}
