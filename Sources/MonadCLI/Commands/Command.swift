import ArgumentParser
import Foundation
import MonadClient

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

// swiftlint:disable:next todo
/// Shell command generation subcommand: `monad cmd find all TODO comments`
struct Command: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cmd",
        abstract: "Generate shell command from natural language"
    )

    @Option(name: .long, help: "Server URL (defaults to auto-discovery or localhost)")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Timeline ID to use")
    var timeline: String?

    @Argument(parsing: .remaining, help: "Description of the task")
    var task: [String]

    func run() async throws {
        let taskText = task.joined(separator: " ")
        guard !taskText.isEmpty else {
            print("Usage: monad cmd <description>")
            print("Example: monad cmd find all TODO comments in Swift files")
            throw ExitCode.failure
        }

        let support = CLICommandSupport(server: server, apiKey: apiKey, verbose: verbose)
        let client = try await support.buildClient()
        let targetTimeline = try await support.resolveTimeline(client: client, explicitTimelineID: timeline)

        // Build command generation prompt
        let systemInfo = gatherSystemInfo()
        let prompt = buildCommandPrompt(task: taskText, systemInfo: systemInfo)

        print(TerminalUI.dim("Analyzing request..."))
        print("")

        let fullResponse = try await streamResponse(client: client, timelineId: targetTimeline.id, message: prompt)
        print("\n")

        // Extract command and offer interactive loop
        guard let command = extractCommand(from: fullResponse) else {
            TerminalUI.printInfo("No command was extracted. Try rephrasing your request.")
            return
        }

        try await commandLoop(command: command, client: client, timeline: targetTimeline)
    }
    // MARK: - Streaming

    private func streamResponse(client: MonadClient, timelineId: UUID, message: String) async throws -> String {
        var fullResponse = ""
        let stream = try await client.chat.execute(timelineId: timelineId, message: message)

        for try await delta in stream {
            if let content = delta.textContent {
                fullResponse += content
                print(content, terminator: "")
                fflush(stdout)
            }
        }
        return fullResponse
    }

    // MARK: - Command Loop

    private func commandLoop(command: String, client: MonadClient, timeline: Timeline) async throws {
        var currentCommand = command

        while true {
            printCommandOptions(currentCommand)

            guard let input = CLIInput.readLine()?.lowercased() else {
                break
            }

            switch input {
            case "r", "run":
                try await runCommand(currentCommand)
                return

            case "e", "edit":
                if let updated = try await editCommand(currentCommand, client: client, timeline: timeline) {
                    currentCommand = updated
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

    private func printCommandOptions(_ command: String) {
        print(TerminalUI.bold("Command:"))
        print("  \(TerminalUI.cyan(command))")
        print("")
        print("Options:")
        print("  \(TerminalUI.bold("[r]"))un       Execute the command")
        print("  \(TerminalUI.bold("[e]"))dit      Describe changes to make")
        print("  \(TerminalUI.bold("[c]"))opy      Copy to clipboard")
        print("  \(TerminalUI.bold("[q]"))uit      Exit")
        print("")
        print("Choice: ", terminator: "")
        fflush(stdout)
    }

    private func editCommand(
        _ currentCommand: String,
        client: MonadClient,
        timeline: Timeline
    ) async throws -> String? {
        guard let feedback = CLIInput.readLine(prompt: "Describe the changes: "), !feedback.isEmpty else {
            return nil
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

        let editResponse = try await streamResponse(client: client, timelineId: timeline.id, message: editPrompt)
        print("\n")

        return extractCommand(from: editResponse)
    }
}

// MARK: - Execution & Helpers

private extension Command {
    func runCommand(_ command: String) async throws {
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

    func copyToClipboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")

        let pipe = Pipe()
        process.standardInput = pipe

        try? process.run()
        pipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    func gatherSystemInfo() -> String {
        var info: [String] = []
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info.append("OS: macOS \(osVersion)")
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            info.append("Shell: \(shell)")
        }
        let cwd = FileManager.default.currentDirectoryPath
        info.append("CWD: \(cwd)")
        info.append("User: \(NSUserName())")
        #if arch(arm64)
            info.append("Arch: arm64 (Apple Silicon)")
        #else
            info.append("Arch: x86_64")
        #endif
        return info.joined(separator: "\n")
    }

    func buildCommandPrompt(task: String, systemInfo: String) -> String {
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

    func extractCommand(from response: String) -> String? {
        let patterns = [
            #"```(?:bash|sh|zsh)?\n?([\s\S]*?)```"#,
            #"`([^`]+)`"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(
                   in: response, range: NSRange(response.startIndex..., in: response)
               ),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: response) {
                let command = String(response[range]).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !command.isEmpty && command.count < 500 {
                    return command
                }
            }
        }
        return nil
    }
}
