import Foundation
import MonadClient
import MonadShared

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

                    var assistantStartPrinted = false
                    var toolCallArgs: [String: String] = [:]
                    var pendingToolCalls: [ToolCall] = []

                    for try await event in stream {
                        if Task.isCancelled { break }

                        switch event {
                        case let .meta(meta):
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

                        case let .delta(delta):
                            switch delta {
                            case let .thinking(thought):
                                if !assistantStartPrinted {
                                    print(TerminalUI.dim("🤔 Thinking..."))
                                    assistantStartPrinted = true
                                }
                                print(TerminalUI.dim(thought), terminator: "")
                                fflush(stdout)

                            case let .generation(content):
                                if !assistantStartPrinted {
                                    TerminalUI.printAssistantStart()
                                    assistantStartPrinted = true
                                }
                                print(content, terminator: "")
                                fflush(stdout)

                            case let .toolCall(delta):
                                if let callId = delta.id {
                                    toolCallArgs[callId] = (toolCallArgs[callId] ?? "") + (delta.arguments ?? "")
                                }

                            case let .toolExecution(toolCallId, status):
                                switch status {
                                case let .attempting(name, ref):
                                    if assistantStartPrinted { print("") }
                                    assistantStartPrinted = false
                                    let args = toolCallArgs[toolCallId] ?? ""
                                    printToolAttempt(name: name, argsJSON: args, reference: ref)
                                default:
                                    break
                                }
                            }

                        case let .error(err):
                            switch err {
                            case let .toolCallError(_, name, error):
                                print(TerminalUI.red("  ✗ Tool Error (\(name)): \(error)"))
                            case let .error(message):
                                print("\n")
                                TerminalUI.printError("Stream Error: \(message)")
                                return
                            case .generationCancelled:
                                print(TerminalUI.yellow("\n[Generation cancelled]"))
                            }

                        case let .completion(completion):
                            switch completion {
                            case let .generationCompleted(msg, meta):
                                if let snapshotData = meta.debugSnapshotData {
                                    updateDebugSnapshot(snapshotData)
                                }
                                let tokens = meta.totalTokens ?? 0
                                let dur = String(format: "%.1fs", meta.duration ?? 0)
                                print(TerminalUI.dim("\n[Generated in \(dur), \(tokens) tokens]"))

                                if let calls = msg.toolCalls, !calls.isEmpty {
                                    pendingToolCalls = calls
                                }

                            case let .toolExecution(_, status):
                                switch status {
                                case let .success(result):
                                    printToolResult(result.output)
                                case let .failed(_, error):
                                    print(TerminalUI.red("  ✗ \(error)"))
                                case let .failure(error):
                                    print(TerminalUI.red("  ✗ \(error)"))
                                default:
                                    break
                                }

                            case .streamCompleted:
                                break
                            }
                        }
                    }

                    if !pendingToolCalls.isEmpty && !Task.isCancelled {
                        print("") // Spacing for local tools

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
                            break
                        }

                        let workspace: WorkspaceReference
                        do {
                            workspace = try await client.workspace.getWorkspace(wsId)
                        } catch {
                            logger.error("Failed to get workspace \(wsId): \(error)")
                            print(TerminalUI.red("  ✗ Cannot execute local tools: could not fetch workspace details."))
                            break
                        }

                        for call in pendingToolCalls {
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

                        let executor = ClientToolExecutor(client: client, timeline: timeline, repl: self)
                        let submissions = await executor.execute(toolCalls: pendingToolCalls, in: workspace)

                        for submission in submissions {
                            if submission.output.hasPrefix("Error:") {
                                print(TerminalUI.red("  ✗ \(submission.output)"))
                            } else {
                                printToolResult(submission.output)
                            }
                        }

                        currentMessage = ""
                        currentToolOutputs = submissions
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
}
