import ArgumentParser
import Foundation
import MonadClient

struct ShellCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "command",
        abstract: "Generate and execute shell commands",
        discussion: """
            Ask the AI to generate a shell command for your task.
            Includes system information for context.

            EXAMPLES:
              monad command "find all large files"
              monad command "compress this folder"
              monad command --single "list running processes"
            """
    )

    @Option(name: .long, help: "Server URL")
    var server: String = "http://127.0.0.1:8080"

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Session ID to use")
    var session: String?

    @Flag(name: .long, help: "Create a new session")
    var new: Bool = false

    @Flag(name: .long, help: "Single query without persisting")
    var single: Bool = false

    @Argument(parsing: .captureForPassthrough, help: "What you want to do")
    var taskParts: [String] = []

    var configuration: ClientConfiguration {
        ClientConfiguration(
            baseURL: URL(string: server) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"],
            verbose: verbose
        )
    }

    func run() async throws {
        let task = taskParts.joined(separator: " ")

        guard !task.isEmpty else {
            TerminalUI.printError("Please describe what you want to do")
            print("Usage: monad command \"find all large files\"")
            throw ExitCode.failure
        }

        let client = MonadClient(configuration: configuration)

        // Check server health
        guard try await client.healthCheck() else {
            TerminalUI.printError("Cannot connect to server at \(server)")
            throw ExitCode.failure
        }

        // Get system info
        let systemInfo = gatherSystemInfo()

        // Determine session
        let sessionId = try await resolveSession(client: client)

        // Build the prompt with system context
        let prompt = buildCommandPrompt(task: task, systemInfo: systemInfo)

        // Get command suggestion
        print(TerminalUI.dim("Analyzing request..."))
        print("")

        var fullResponse = ""
        do {
            let stream = try await client.chatStream(sessionId: sessionId, message: prompt)

            for try await delta in stream {
                if let content = delta.content {
                    fullResponse += content
                    print(content, terminator: "")
                    fflush(stdout)
                }
            }
            print("\n")
        } catch let error as MonadClientError {
            switch error {
            case .unauthorized:
                TerminalUI.printError("Authentication failed")
                print(
                    "  Hint: Check your API key in /config (for Provider) or MONAD_API_KEY (for Server)"
                )
            case .serverNotReachable, .networkError:
                TerminalUI.printError("Cannot reach server")
                print("  Hint: Ensure the server is running with 'make run-server'")
            case .notFound:
                TerminalUI.printError("Session not found")
                print("  Hint: Use --new to create a fresh session")
            default:
                TerminalUI.printError(error.localizedDescription)
            }
            throw ExitCode.failure
        } catch {
            TerminalUI.printError("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Extract command from response
        guard let command = extractCommand(from: fullResponse) else {
            TerminalUI.printInfo("No command was extracted. Try rephrasing your request.")
            return
        }

        // Interactive loop
        try await commandLoop(client: client, sessionId: sessionId, command: command)
    }

    // MARK: - Session Management

    private func resolveSession(client: MonadClient) async throws -> UUID {
        // 1. Explicit flags take precedence
        if single {
            return try await client.createSession().id
        }
        if new {
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            TerminalUI.printInfo("Created new session \(session.id.uuidString.prefix(8))")
            return session.id
        }

        // 2. Try specified session
        if let sessionString = session, let uuid = UUID(uuidString: sessionString) {
            do {
                _ = try await client.getHistory(sessionId: uuid)
                return uuid
            } catch {
                TerminalUI.printWarning("Specified session \(uuid.uuidString.prefix(8)) not found.")
                // Fallthrough to interactive selection
            }
        }

        // 3. Try persisted session
        if let savedUUID = loadCurrentSession() {
            do {
                _ = try await client.getHistory(sessionId: savedUUID)
                return savedUUID
            } catch {
                // Saved session invalid or not found, fallthrough to selection
            }
        }

        // 4. No valid session context -> Interactive selection
        return try await interactiveSessionSelection(client: client)
    }

    private func interactiveSessionSelection(client: MonadClient) async throws -> UUID {
        print("")
        TerminalUI.printInfo("No active session found. Choose an option:")
        print("  1. Create new session (default)")
        print("  2. Select from recent sessions")
        print("  3. Temporary session (one-off)")
        print("")
        print("Choice [1]: ", terminator: "")

        let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""

        switch choice {
        case "2":
            return try await selectExistingSession(client: client)
        case "3":
            return try await client.createSession().id
        default:
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            TerminalUI.printInfo("Created session \(session.id.uuidString.prefix(8))")
            return session.id
        }
    }

    private func selectExistingSession(client: MonadClient) async throws -> UUID {
        let sessions = try await client.listSessions()
        guard !sessions.isEmpty else {
            TerminalUI.printWarning("No existing sessions found.")
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            return session.id
        }

        print("")
        print(TerminalUI.bold("Recent Sessions:"))
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }

        for (i, s) in sorted.prefix(5).enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: s.updatedAt)

            let title = s.title ?? "Untitled Session"
            let idPrefix = s.id.uuidString.prefix(8)
            print("  \(i+1). \(title) (\(idPrefix)) - \(dateStr)")
        }
        print("")
        print("Select session (1-\(min(sorted.count, 5))): ", terminator: "")

        if let input = readLine(), let index = Int(input),
            index > 0 && index <= min(sorted.count, 5)
        {
            let session = sorted[index - 1]
            saveCurrentSession(session.id)
            print(TerminalUI.dim("Attached to session \(session.id.uuidString.prefix(8))"))
            return session.id
        }

        TerminalUI.printWarning("Invalid selection. Creating new session.")
        let session = try await client.createSession()
        saveCurrentSession(session.id)
        return session.id
    }

    // MARK: - System Info

    private func gatherSystemInfo() -> String {
        var info: [String] = []

        // OS
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        info.append("OS: macOS \(os)")

        // Shell
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            info.append("Shell: \(shell)")
        }

        // Current directory
        let cwd = FileManager.default.currentDirectoryPath
        info.append("CWD: \(cwd)")

        // User
        info.append("User: \(NSUserName())")

        // Home
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        info.append("Home: \(home)")

        // Architecture
        #if arch(arm64)
            info.append("Arch: arm64 (Apple Silicon)")
        #else
            info.append("Arch: x86_64")
        #endif

        return info.joined(separator: "\n")
    }

    private func buildCommandPrompt(task: String, systemInfo: String) -> String {
        """
        I need a shell command to: \(task)

        System Information:
        \(systemInfo)

        Please provide:
        1. The exact command to run (wrapped in ```bash...```)
        2. A brief explanation of what it does
        3. Any warnings or considerations

        Keep the response concise. Focus on giving me a working command.
        """
    }

    // MARK: - Command Extraction

    private func extractCommand(from response: String) -> String? {
        // Look for ```bash ... ``` or ```sh ... ``` or ``` ... ```
        let patterns = [
            #"```(?:bash|sh|zsh)?\n?([\s\S]*?)```"#,
            #"`([^`]+)`"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                let match = regex.firstMatch(
                    in: response, range: NSRange(response.startIndex..., in: response)),
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: response)
            {
                let command = String(response[range]).trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if !command.isEmpty && command.count < 500 {  // Sanity check
                    return command
                }
            }
        }

        return nil
    }

    // MARK: - Interactive Loop

    private func commandLoop(client: MonadClient, sessionId: UUID, command: String) async throws {
        var currentCommand = command

        while true {
            print(TerminalUI.bold("Command:"))
            print("  \(TerminalUI.cyan(currentCommand))")
            print("")
            print("Options:")
            print("  \(TerminalUI.bold("[r]"))un       Execute the command")
            print("  \(TerminalUI.bold("[p]"))ipe      Run and send output back to chat")
            print("  \(TerminalUI.bold("[e]"))dit      Describe changes to make")
            print("  \(TerminalUI.bold("[c]"))opy      Copy to clipboard")
            print("  \(TerminalUI.bold("[q]"))uit      Exit")
            print("")
            print("Choice: ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) else {
                break
            }

            switch input {
            case "r", "run":
                try await runCommand(currentCommand)
                return

            case "p", "pipe":
                let output = try await runCommandWithOutput(currentCommand)
                print("")
                print(TerminalUI.dim("--- Command Output ---"))
                print(output)
                print(TerminalUI.dim("--- End Output ---"))
                print("")

                // Send output back to chat
                let followUp = """
                    The command output was:
                    ```
                    \(output.prefix(2000))
                    ```
                    What should I do next? Or is there a better approach?
                    """

                print(TerminalUI.dim("Analyzing output..."))
                print("")

                var newResponse = ""
                let stream = try await client.chatStream(sessionId: sessionId, message: followUp)
                for try await delta in stream {
                    if let content = delta.content {
                        newResponse += content
                        print(content, terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n")

                // Check if there's a new command suggestion
                if let newCommand = extractCommand(from: newResponse) {
                    currentCommand = newCommand
                    continue
                }
                return

            case "e", "edit":
                print("Describe the changes: ", terminator: "")
                fflush(stdout)
                guard let feedback = readLine(), !feedback.isEmpty else {
                    continue
                }

                let editPrompt = """
                    Modify this command based on feedback:
                    Current command: `\(currentCommand)`

                    Feedback: \(feedback)

                    Provide the updated command in ```bash...``` format.
                    """

                print("")
                print(TerminalUI.dim("Updating command..."))
                print("")

                var editResponse = ""
                let stream = try await client.chatStream(sessionId: sessionId, message: editPrompt)
                for try await delta in stream {
                    if let content = delta.content {
                        editResponse += content
                        print(content, terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n")

                if let newCommand = extractCommand(from: editResponse) {
                    currentCommand = newCommand
                }
                continue

            case "c", "copy":
                copyToClipboard(currentCommand)
                TerminalUI.printSuccess("Copied to clipboard")
                continue

            case "q", "quit", "":
                return

            default:
                TerminalUI.printError("Unknown option: \(input)")
                continue
            }
        }
    }

    private func runCommand(_ command: String) async throws {
        print("")
        print(TerminalUI.dim("$ \(command)"))
        print("")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Stream output
        let handle = pipe.fileHandleForReading
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            if let str = String(data: data, encoding: .utf8) {
                print(str, terminator: "")
                fflush(stdout)
            }
        }

        process.waitUntilExit()

        print("")
        if process.terminationStatus == 0 {
            TerminalUI.printSuccess("Command completed successfully")
        } else {
            TerminalUI.printError("Command exited with status \(process.terminationStatus)")
        }
    }

    private func runCommandWithOutput(_ command: String) async throws -> String {
        print("")
        print(TerminalUI.dim("$ \(command)"))
        print("")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func copyToClipboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")

        let pipe = Pipe()
        process.standardInput = pipe

        try? process.run()
        pipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    // MARK: - Session Persistence

    private func sessionFilePath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".monad_session")
    }

    private func loadCurrentSession() -> UUID? {
        let path = sessionFilePath()
        guard let data = try? Data(contentsOf: path),
            let string = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            let uuid = UUID(uuidString: string)
        else {
            return nil
        }
        return uuid
    }

    private func saveCurrentSession(_ id: UUID) {
        let path = sessionFilePath()
        try? id.uuidString.write(to: path, atomically: true, encoding: .utf8)
    }
}
