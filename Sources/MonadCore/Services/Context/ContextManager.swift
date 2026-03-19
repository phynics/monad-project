import Dependencies
import ErrorKit
import Foundation
import Logging
import MonadShared

/// Manages the retrieval and organization of context for the chat
public actor ContextManager {
    @Dependency(\.memoryStore) var memoryStore
    @Dependency(\.embeddingService) var embeddingService

    public let workspace: (any WorkspaceProtocol)?
    private let customPipeline: ContextPipeline?
    let logger = Logger.module(named: "com.monad.ContextManager")

    let ranker = ContextRanker()

    public init(
        workspace: (any WorkspaceProtocol)? = nil,
        pipeline: ContextPipeline? = nil
    ) {
        self.workspace = workspace
        self.customPipeline = pipeline
    }

    /// The pipeline used for context gathering. 
    /// Returns the custom pipeline if provided, otherwise the default pipeline.
    public var pipeline: ContextPipeline {
        customPipeline ?? ContextPipeline {
            QueryAugmentationStage(manager: self)
            MemoryRetrievalStage(manager: self)
            NoteDiscoveryStage(manager: self)
            ContextAssemblyStage(logger: logger)
        }
    }

    /// Gather all relevant context for a given user query
    /// - Parameters:
    ///   - query: The user's input text
    ///   - history: Recent conversation history to provide context for the search
    ///   - limit: Maximum number of memories to retrieve
    ///   - tagGenerator: A function to generate tags from the query (e.g. via LLM)
    /// - Returns: A stream of progress events, finishing with the structured context
    public func gatherContext(
        for query: String,
        history: [Message] = [],
        limit: Int = 5,
        tagGenerator: (@Sendable (String) async throws -> [String])? = nil
    ) -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        return AsyncThrowingStream<ContextGatheringEvent, Error> { continuation in
            let task = Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                logger.debug(
                    "Gathering context for query length: \(query.count), history count: \(history.count)"
                )

                let context = ContextPipelineContext(
                    query: query,
                    history: history,
                    limit: limit,
                    tagGenerator: tagGenerator,
                    startTime: startTime
                )

                do {
                    let stream = pipeline.execute(context)
                    for try await event in stream {
                        continuation.yield(event)
                    }

                    if let data = await context.contextData {
                        continuation.yield(.progress(.complete))
                        continuation.yield(.complete(data))
                    }
                    continuation.finish()
                } catch {
                    logger.error("Context gathering failed: \(ErrorKit.userFriendlyMessage(for: error))")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func fetchAllNotes() async throws -> [ContextFile] {
        var allNotes: [ContextFile] = []

        if let workspace = workspace {
            do {
                let files = try await workspace.listFiles(path: "Notes")

                for filePath in files where filePath.hasSuffix(".md") {
                    guard let content = try? await workspace.readFile(path: filePath) else {
                        continue
                    }
                    let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent

                    let note = ContextFile(
                        name: name,
                        content: content,
                        source: filePath
                    )
                    allNotes.append(note)
                }
            } catch {
                logger.warning(
                    "Failed to fetch notes from workspace: \(ErrorKit.userFriendlyMessage(for: error))"
                )
            }
        }

        return allNotes.sorted(by: { $0.name < $1.name })
    }

    public nonisolated func buildAugmentedContext(query: String, history: [Message]) -> String {
        guard !history.isEmpty else { return query }

        // Take the last few user/assistant messages to provide context for tags
        // Exclude tool responses as they might be too technical/long for tag generation context
        let historyContext =
            history
                .filter { $0.role == .user || $0.role == .assistant }
                .suffix(3)
                .map { $0.content }
                .joined(separator: " ")

        if historyContext.isEmpty { return query }

        let augmented = "\(historyContext) \(query)"
        logger.debug("Augmented tag context: \(augmented)")
        return augmented
    }
}
