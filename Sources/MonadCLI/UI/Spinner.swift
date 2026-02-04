import Foundation

/// A simple terminal spinner for async operations
public final class Spinner: Sendable {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let interval: UInt64 = 80_000_000  // 80ms
    private let message: String

    // Thread-safe state coordination
    private actor State {
        var task: Task<Void, Never>?

        func start(message: String, frames: [String], interval: UInt64) {
            cancel()

            task = Task {
                var index = 0
                print("", terminator: "")  // Flush needed?

                // Hide cursor
                print("\u{001B}[?25l", terminator: "")
                fflush(stdout)

                while !Task.isCancelled {
                    let frame = frames[index % frames.count]
                    // Clear line, Print frame + message
                    print("\r\(TerminalUI.cyan(frame)) \(message)", terminator: "")
                    fflush(stdout)

                    index += 1
                    try? await Task.sleep(nanoseconds: interval)
                }
            }
        }

        func stop(finalMessage: String?, symbol: String?) {
            task?.cancel()
            task = nil

            // Clear line
            print("\r\u{001B}[2K", terminator: "")

            if let msg = finalMessage {
                let sym = symbol ?? "✓"
                print("\(TerminalUI.green(sym)) \(msg)")
            } else {
                // Return cursor to start of line
                print("\r", terminator: "")
            }

            // Show cursor
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
        }

        func cancel() {
            task?.cancel()
            task = nil
            // Ensure cursor is shown if we cancel abruptly
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
        }
    }

    private let state = State()

    public init(message: String) {
        self.message = message
    }

    public func start() async {
        await state.start(message: message, frames: frames, interval: interval)
    }

    public func stop(message: String? = nil, symbol: String? = nil) async {
        await state.stop(finalMessage: message, symbol: symbol)
    }
}
