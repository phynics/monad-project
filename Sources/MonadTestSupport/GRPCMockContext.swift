import Foundation
import GRPC
import NIOHPACK
import Logging
import MonadCore

public struct MockServerContext: MonadServerContext {
    public var logger: Logger = Logger(label: "mock")
    public init() {}
}

/// A collection of utilities for testing gRPC handlers.
public enum GRPCMockEnvironment {
    /// Creates a mock response stream writer and its backing stream for testing.
    public static func makeWriter<T: Sendable>(
        responseType: T.Type = T.self
    ) -> (writer: GRPCAsyncResponseStreamWriter<T>, stream: GRPCAsyncResponseStreamWriter<T>.ResponseStream) {
        let testingWriter = GRPCAsyncResponseStreamWriter<T>.makeTestingResponseStreamWriter()
        return (testingWriter.writer, testingWriter.stream)
    }
}