import MonadShared
import MonadCore
import Foundation

#if DEBUG
extension AsyncStream {
    /// Collects all elements of the stream into an array.
    /// Only works for finite streams.
    public func collect() async -> [Element] {
        var result: [Element] = []
        for await element in self {
            result.append(element)
        }
        return result
    }
}

extension AsyncThrowingStream {
    /// Collects all elements of the stream into an array.
    /// Only works for finite streams.
    public func collect() async throws -> [Element] {
        var result: [Element] = []
        for try await element in self {
            result.append(element)
        }
        return result
    }
}

public func getTestWorkspaceRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("com.monad.test-workspaces")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
#endif
