import Foundation
import Synchronization
import PKShared
import MonadShared

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Manages terminal raw mode state
public final class TerminalRawMode: Sendable {
    private let originalTerm = Mutex<termios?>(nil)

    public init() {}

    public func enable() {
        var term = termios()
        tcgetattr(STDIN_FILENO, &term)
        originalTerm
            .withLock { $0 = term }

        var raw = TerminalInputMode.makeRaw(term, interceptSignals: true)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    public func disable() {
        originalTerm.withLock {
            if let term = $0 {
                var termCopy = term
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &termCopy)
                $0 = nil
            }
        }
    }
}
