import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum TerminalInputMode {
    static func makeRaw(_ term: termios, interceptSignals: Bool) -> termios {
        var raw = term

#if canImport(Darwin)
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        if interceptSignals {
            raw.c_lflag &= ~UInt(ISIG)
        }
        raw.c_cc.16 = 1 // VMIN
        raw.c_cc.17 = 0 // VTIME
#else
        raw.c_lflag &= ~UInt32(ECHO | ICANON)
        if interceptSignals {
            raw.c_lflag &= ~UInt32(ISIG)
        }
        raw.c_cc.6 = 1 // VMIN
        raw.c_cc.7 = 0 // VTIME
#endif

        return raw
    }
}
