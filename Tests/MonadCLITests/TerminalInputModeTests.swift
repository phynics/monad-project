import Testing
@testable import MonadCLI

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite struct TerminalInputModeTests {
    @Test("raw mode for CLI input disables canonical processing, echo, and terminal-generated signals")
    func rawModeInterceptsCtrlC() {
        var term = termios()
#if canImport(Darwin)
        term.c_lflag = UInt(ECHO | ICANON | ISIG)
#else
        term.c_lflag = UInt32(ECHO | ICANON | ISIG)
#endif

        let raw = TerminalInputMode.makeRaw(term, interceptSignals: true)

#if canImport(Darwin)
        #expect((raw.c_lflag & UInt(ECHO)) == 0)
        #expect((raw.c_lflag & UInt(ICANON)) == 0)
        #expect((raw.c_lflag & UInt(ISIG)) == 0)
        #expect(raw.c_cc.16 == 1)
        #expect(raw.c_cc.17 == 0)
#else
        #expect((raw.c_lflag & UInt32(ECHO)) == 0)
        #expect((raw.c_lflag & UInt32(ICANON)) == 0)
        #expect((raw.c_lflag & UInt32(ISIG)) == 0)
        #expect(raw.c_cc.6 == 1)
        #expect(raw.c_cc.7 == 0)
#endif
    }
}
