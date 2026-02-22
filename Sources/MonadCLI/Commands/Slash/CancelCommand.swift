import Foundation
import MonadClient
import MonadShared

/// Cancel an ongoing generation
struct CancelCommand: SlashCommand {
    let name = "cancel"
    let description = "Cancel the currently active generation"
    let aliases: [String] = []

    func run(args: [String], context: ChatContext) async throws {
        try await context.client.cancelChat(sessionId: context.session.id)
        await context.repl.cancelCurrentGeneration()
        context.output.printWarning("Cancellation signal sent.")
    }
}
