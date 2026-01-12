import Foundation
import GRPC
import Logging

/// Protocol for abstraction of gRPC server call context to enable mocking
public protocol MonadServerContext: Sendable {
    var logger: Logger { get }
}

extension GRPCAsyncServerCallContext: MonadServerContext {
    public var logger: Logger { self.request.logger }
}
