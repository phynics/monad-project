import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Handles raw terminal input for line editing, history, and autocomplete
final class LineReader {
    private var history: [String] = []
    private var historyIndex: Int = 0
    private var buffer: [Character] = []
    private var cursorIndex: Int = 0
    private var prompt: String

    // Configuration
    private var originalTerm: termios = .init()
    private var isRawMode = false

    init(prompt: String = "> ", history: [String] = []) {
        self.prompt = prompt
        self.history = history
        historyIndex = history.count
    }

    /// Read a line of input with support for editing and history
    func readLine(prompt: String? = nil, completion: ((String) -> [String])? = nil) -> String? {
        if let newPrompt = prompt { self.prompt = newPrompt }
        enableRawMode()
        defer { disableRawMode() }

        buffer = []
        cursorIndex = 0
        historyIndex = history.count

        // Print prompt initially
        print(self.prompt, terminator: "")
        fflush(stdout)

        while true {
            guard let char = readChar() else { return nil }

            let result = processInputCharacter(char, completion: completion)
            switch result {
            case .continueReading:
                refreshLine()
            case let .finished(value):
                return value
            case .cancelled:
                return nil
            }
        }
    }

    // MARK: - Input Processing

    private enum InputResult {
        case continueReading
        case finished(String)
        case cancelled
    }

    private func processInputCharacter(
        _ char: Character,
        completion: ((String) -> [String])?
    ) -> InputResult {
        switch char {
        case "\u{7F}": // Backspace
            handleBackspace()
        case "\r", "\n": // Enter
            return finishInput()
        case "\t": // Tab
            if let handler = completion {
                handleTab(handler: handler)
            }
        case "\u{1B}": // Escape sequence
            handleEscapeSequence()
        case "\u{03}": // Ctrl+C
            return .cancelled
        case "\u{04}": // Ctrl+D (EOF)
            if buffer.isEmpty { return .cancelled }
        default:
            if !char.isControl {
                insertCharacter(char)
            }
        }
        return .continueReading
    }

    private func finishInput() -> InputResult {
        print("\n", terminator: "")
        let result = String(buffer)
        if !result.isEmpty {
            history.append(result)
            historyIndex = history.count
        }
        return .finished(result)
    }

    // MARK: - Terminal Control

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTerm)
        var raw = originalTerm

        // Disable ECHO and ICANON (canonical mode)
        #if canImport(Darwin)
            raw.c_lflag &= ~UInt(ECHO | ICANON)
        #else
            raw.c_lflag &= ~UInt32(ECHO | ICANON)
        #endif

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRawMode = true
    }

    private func disableRawMode() {
        if isRawMode {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTerm)
            isRawMode = false
        }
    }

    private func readChar() -> Character? {
        var byte: UInt8 = 0
        let bytesRead = read(STDIN_FILENO, &byte, 1)
        if bytesRead <= 0 { return nil }
        return Character(UnicodeScalar(byte))
    }

    // MARK: - Editing Actions

    private func insertCharacter(_ char: Character) {
        if cursorIndex == buffer.count {
            buffer.append(char)
        } else {
            buffer.insert(char, at: cursorIndex)
        }
        cursorIndex += 1
    }

    private func handleBackspace() {
        if cursorIndex > 0 {
            buffer.remove(at: cursorIndex - 1)
            cursorIndex -= 1
        }
    }

    private func handleTab(handler: (String) -> [String]) {
        let current = String(buffer)
        let candidates = handler(current)

        if candidates.isEmpty { return }

        if candidates.count == 1 {
            // Apply unique completion
            replaceBuffer(with: candidates[0])
        } else {
            // Partial completion: Find longest common prefix
            let prefix = longestCommonPrefix(of: candidates)
            if !prefix.isEmpty, prefix.count > current.count {
                replaceBuffer(with: prefix)
            }
            // Optional: Print candidates? (Complex in raw mode, skipping for now)
        }
    }

    private func longestCommonPrefix(of strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var prefix = first

        for str in strings.dropFirst() {
            while !str.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }

    // MARK: - Navigation

    private func handleEscapeSequence() {
        // Read next 2 bytes for [A, [B, etc.
        guard let byte1 = readChar(), byte1 == "[" else { return }
        guard let byte2 = readChar() else { return }

        switch byte2 {
        case "A": // Up
            navigateHistory(offset: -1)
        case "B": // Down
            navigateHistory(offset: 1)
        case "C": // Right
            moveCursor(offset: 1)
        case "D": // Left
            moveCursor(offset: -1)
        default:
            break
        }
    }

    private func navigateHistory(offset: Int) {
        let newIndex = historyIndex + offset
        if newIndex >= 0, newIndex <= history.count {
            historyIndex = newIndex
            if newIndex == history.count {
                replaceBuffer(with: "")
            } else {
                replaceBuffer(with: history[newIndex])
            }
        }
    }

    private func moveCursor(offset: Int) {
        let newPos = cursorIndex + offset
        if newPos >= 0, newPos <= buffer.count {
            cursorIndex = newPos
        }
    }

    private func replaceBuffer(with text: String) {
        buffer = Array(text)
        cursorIndex = buffer.count
    }

    // MARK: - Rendering

    private func stripAnsi(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "\u{001B}\\[[;\\d]*[mK]", with: "", options: .regularExpression
        )
    }

    private func refreshLine() {
        // Carriage return to start
        print("\r", terminator: "")

        // Print prompt and buffer
        print(prompt, terminator: "")
        print(String(buffer), terminator: "")

        // Clear remaining line (if buffer shrunk)
        print("\u{1B}[K", terminator: "")

        // Move cursor back to correct position
        let promptLen = stripAnsi(prompt).count
        let totalLen = promptLen + buffer.count
        let targetLen = promptLen + cursorIndex
        if totalLen > targetLen {
            print("\u{1B}[\(totalLen - targetLen)D", terminator: "")
        }

        fflush(stdout)
    }
}

extension Character {
    var isControl: Bool {
        return isASCII && (whichASCIIValue ?? 0) < 32
    }

    var whichASCIIValue: UInt8? {
        if let scalar = unicodeScalars.first, scalar.isASCII {
            return UInt8(scalar.value)
        }
        return nil
    }
}
