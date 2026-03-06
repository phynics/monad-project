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
    }
}
