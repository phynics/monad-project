import Foundation
import GRPC
import NIOHPACK
import Logging
import MonadCore

public struct MockServerContext: MonadServerContext {
    public var logger: Logger = Logger(label: "mock")
    public init() {}
}
