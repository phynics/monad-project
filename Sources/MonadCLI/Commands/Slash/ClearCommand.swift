import Foundation
import MonadClient

/// Clear the terminal screen
struct ClearCommand: SlashCommand {
    let name = "clear"
    let aliases = ["cls"]
    let description = "Clear the terminal screen"
    let category: String? = "General"

    func run(args: [String], context: ChatContext) async throws {
        // ANSI escape sequence to clear screen and move cursor to top-left
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }
}
