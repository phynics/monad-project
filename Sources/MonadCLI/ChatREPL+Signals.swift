import Foundation
import MonadClient

extension ChatREPL {
    func setupSignalHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleSigint()
            }
        }
        source.resume()
        signalSource = source
        // Ignore SIGINT in the main process to prevent it from killing us
        signal(SIGINT, SIG_IGN)
    }

    func handleSigint() async {
        let now = Date()
        let isDoubleTap: Bool
        if let last = lastSigintTime, now.timeIntervalSince(last) < 1.0 {
            isDoubleTap = true
        } else {
            isDoubleTap = false
        }
        lastSigintTime = now

        if isDoubleTap {
            TerminalUI.printInfo("\n\nGoodbye!")
            running = false
            exit(0)
        }

        if currentGenerationTask != nil {
            await cancelCurrentGeneration()
        } else {
            print("")
            TerminalUI.printInfo("Goodbye! (Press Ctrl-C again to force quit)")
            running = false
            exit(0)
        }
    }

    func cancelCurrentGeneration() async {
        if let task = currentGenerationTask {
            task.cancel()
            currentGenerationTask = nil
            TerminalUI.printWarning("\n[Cancelling generation...]")
            try? await client.chat.cancelChat(timelineId: timeline.id)
        }
        stopEscapeMonitor()
    }

    func startEscapeMonitor() {
        stopEscapeMonitor()

        escapeMonitorTask = Task.detached { [weak self] in
            let rawMode = TerminalRawMode()
            rawMode.enable()
            defer { rawMode.disable() }

            var lastEscapeTime: Date?

            while !Task.isCancelled {
                var byte: UInt8 = 0
                let bytesRead = read(STDIN_FILENO, &byte, 1)

                if bytesRead <= 0 {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }

                let char = Character(UnicodeScalar(byte))
                if char == "\u{1B}" {
                    let now = Date()
                    if let last = lastEscapeTime, now.timeIntervalSince(last) < 0.5 {
                        // Double escape detected!
                        if let self = self {
                            await self.cancelCurrentGeneration()
                        }
                        lastEscapeTime = nil
                    } else {
                        lastEscapeTime = now
                    }
                } else if byte == 3 { // Ctrl-C
                    // The signal handler should handle this, but in raw mode we might catch it here
                    if let self = self {
                        await self.handleSigint()
                    }
                } else {
                    lastEscapeTime = nil
                }
            }
        }
    }

    func stopEscapeMonitor() {
        escapeMonitorTask?.cancel()
        escapeMonitorTask = nil
    }
}
