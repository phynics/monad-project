import MonadShared
import os

/// A thread-safe wrapper around a value.
public final class Locked<T: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<T>

    public init(_ value: T) {
        self.lock = OSAllocatedUnfairLock(initialState: value)
    }

    public var value: T {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    public func withLock<R: Sendable>(_ body: @Sendable (inout T) throws -> R) rethrows -> R {
        try lock.withLock(body)
    }
}
