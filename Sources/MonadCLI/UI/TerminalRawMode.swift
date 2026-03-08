import Foundation
import Synchronization
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

        var raw = term
#if canImport(Darwin)
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        // We want to be able to read without blocking indefinitely if possible,
        // but for a background task, blocking read is fine.
        raw.c_cc.16 = 1 // VMIN
        raw.c_cc.17 = 0 // VTIME
#else
        raw.c_lflag &= ~UInt32(ECHO | ICANON)
        raw.c_cc.6 = 1 // VMIN
        raw.c_cc.7 = 0 // VTIME
#endif

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
