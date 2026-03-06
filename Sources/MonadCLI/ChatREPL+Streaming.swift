import Foundation
import MonadClient

// Needed for fflush
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

extension ChatREPL {
    func sendMessage(_ message: String) async {
        if !lastServerStatus {
            TerminalUI.printError("Server is offline. Check connection and try again.")
            return
        }

        let sessionId = session.id
        currentGenerationTask = Task {
            do {
                print("")

                let stream = try await client.chatStream(sessionId: sessionId, message: message)

                var assistantStartPrinted = false
                // Accumulate streamed argument JSON fragments per toolCallId for display
                var toolCallArgs: [String: String] = [:]

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
                            // Accumulate argument JSON fragments so we can display them on execution
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
                        case .cancelled:
                            print(TerminalUI.yellow("\n[Generation cancelled]"))
                        }

                    case let .completion(completion):
                        switch completion {
                        case let .generationCompleted(_, meta):
                            if let snapshotData = meta.debugSnapshotData {
                                updateDebugSnapshot(snapshotData)
                            }
                            let tokens = meta.totalTokens ?? 0
                            let dur = String(format: "%.1fs", meta.duration ?? 0)
                            print(TerminalUI.dim("\n[Generated in \(dur), \(tokens) tokens]"))

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

            } catch {
                if !(error is CancellationError) {
                    print("")
                    await handleError(error)
                }
            }
        }
        await currentGenerationTask?.value
        currentGenerationTask = nil
    }
}
