import ArgumentParser
import MonadCLICore
import MonadServerCore

@main
struct Monad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad",
        abstract: "Monad AI Assistant",
        discussion: """
        `monad` with no subcommand runs `monad chat`.

        CLIENT commands (talk to an already-running server; never start one):
          chat      Interactive REPL (default)
          query     One-shot prompt, print the reply, exit
          command   Run a single slash-style command non-interactively
          status    Check which server the client would use, and whether it's reachable

        Client commands share `--server <url>` to pick which server they talk to
        (falls back to saved config, then auto-discovery, then http://127.0.0.1:8080)
        and `--api-key <key>` for authentication.

        SERVER command (binds and runs the Monad server process itself):
          server    Start the HTTP/SSE/WebSocket server (`--hostname`/`--port` to bind)

        `monad server` and the client commands are independent processes: run
        `monad server` in one terminal, then `monad`/`monad chat` in another.
        Client commands never start, stop, or manage a server for you.
        """,
        subcommands: [Chat.self, Server.self, Status.self, Query.self, Command.self],
        defaultSubcommand: Chat.self
    )
}
