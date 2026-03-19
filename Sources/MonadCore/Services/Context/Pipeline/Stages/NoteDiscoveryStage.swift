import ErrorKit
import Foundation
import Logging
import MonadShared

/// Pipeline stage responsible for discovering relevant filesystem notes in the workspace.
public struct NoteDiscoveryStage: PipelineStage {
    public let workspace: (any WorkspaceProtocol)?
    private let logger = Logger.module(named: "com.monad.NoteDiscoveryStage")

    public init(workspace: (any WorkspaceProtocol)? = nil) {
        self.workspace = workspace
    }

    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.progress(.discoveringNotes))
                let notes = (try? await fetchAllNotes()) ?? []
                await context.setResults(notes: notes)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func fetchAllNotes() async throws -> [ContextFile] {
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
}
