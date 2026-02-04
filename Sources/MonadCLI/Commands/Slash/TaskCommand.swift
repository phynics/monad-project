import Foundation
import MonadClient

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

struct TaskCommand: SlashCommand {
    let name = "task"
    let aliases = ["shell", "cmd"]
    let description = "Generate and execute shell commands"
    let category: String? = "Tools & Environment"
    let usage = "/task <description>"

    func run(args: [String], context: ChatContext) async throws {
        let task = args.joined(separator: " ")
        guard !task.isEmpty else {
            TerminalUI.printError("Usage: /task <description>")
            return
        }

        let systemInfo = gatherSystemInfo()
        let prompt = buildCommandPrompt(task: task, systemInfo: systemInfo)

        print(TerminalUI.dim("Analyzing request..."))
        print("")

        var fullResponse = ""
        do {
            // Use current session
            let stream = try await context.client.chatStream(
                sessionId: context.session.id, message: prompt)

            for try await delta in stream {
                if let content = delta.content {
                    fullResponse += content
                    print(content, terminator: "")
                    fflush(stdout)
                }
            }
            print("\n")
        } catch {
            TerminalUI.printError("Error: \(error.localizedDescription)")
            return
        }

        // Extract command from response
        guard let command = extractCommand(from: fullResponse) else {
            TerminalUI.printInfo("No command was extracted. Try rephrasing your request.")
            return
        }

        // Interactive loop
        try await commandLoop(command: command, context: context)
    }

    // MARK: - Loop

    private func commandLoop(command: String, context: ChatContext) async throws {
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
            print("  \(TerminalUI.bold("[q]"))uit      Exit to chat")
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
                let stream = try await context.client.chatStream(
                    sessionId: context.session.id, message: followUp)
                for try await delta in stream {
                    if let content = delta.content {
                        newResponse += content
                        print(content, terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n")

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
                let stream = try await context.client.chatStream(
                    sessionId: context.session.id, message: editPrompt)
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

    // MARK: - Execution

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

    // MARK: - Helpers

    private func gatherSystemInfo() -> String {
        var info: [String] = []
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        info.append("OS: macOS \(os)")
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

    private func extractCommand(from response: String) -> String? {
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
                if !command.isEmpty && command.count < 500 {
                    return command
                }
            }
        }
        return nil
    }
}
