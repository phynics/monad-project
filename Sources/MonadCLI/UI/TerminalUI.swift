import Foundation

/// Terminal UI utilities with ANSI color support
public enum TerminalUI {
    // MARK: - ANSI Color Codes

    private static let reset = "\u{001B}[0m"
    private static let boldCode = "\u{001B}[1m"
    private static let dimCode = "\u{001B}[2m"

    private static let redCode = "\u{001B}[31m"
    private static let greenCode = "\u{001B}[32m"
    private static let yellowCode = "\u{001B}[33m"
    private static let blueCode = "\u{001B}[34m"
    private static let magentaCode = "\u{001B}[35m"
    private static let cyanCode = "\u{001B}[36m"

    // MARK: - Text Formatting

    public static func bold(_ text: String) -> String {
        "\(boldCode)\(text)\(reset)"
    }

    public static func dim(_ text: String) -> String {
        "\(dimCode)\(text)\(reset)"
    }

    public static func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }

    public static func red(_ text: String) -> String {
        "\(redCode)\(text)\(reset)"
    }

    public static func green(_ text: String) -> String {
        "\(greenCode)\(text)\(reset)"
    }

    public static func yellow(_ text: String) -> String {
        "\(yellowCode)\(text)\(reset)"
    }

    public static func blue(_ text: String) -> String {
        "\(blueCode)\(text)\(reset)"
    }

    public static func magenta(_ text: String) -> String {
        "\(magentaCode)\(text)\(reset)"
    }

    public static func cyan(_ text: String) -> String {
        "\(cyanCode)\(text)\(reset)"
    }

    // MARK: - Role Colors

    public static func userColor(_ text: String) -> String {
        cyan(text)
    }

    public static func assistantColor(_ text: String) -> String {
        magenta(text)
    }

    public static func systemColor(_ text: String) -> String {
        yellow(text)
    }

    public static func toolColor(_ text: String) -> String {
        blue(text)
    }

    public static func printToolCall(name: String, args: String) {
        let argsPreview = args.count > 40 ? "\(args.prefix(40))..." : args
        print("\(toolColor("🛠️ Calling \(name)"))\(dim("(" + argsPreview + ")"))", terminator: "")
        fflush(stdout)
    }

    // MARK: - Messages

    public static func printError(_ message: String) {
        fputs("\(red("Error:")) \(message)\n", stderr)
    }

    public static func printWarning(_ message: String) {
        print("\(yellow("Warning:")) \(message)")
    }

    public static func printInfo(_ message: String) {
        print("\(dim("ℹ")) \(message)")
    }

    public static func printSuccess(_ message: String) {
        print("\(green("✓")) \(message)")
    }

    // MARK: - Chat UI

    // MARK: - Logo

    public static func printLogo() {
        let logo = """
            \(magenta("  __  __                       _ "))
            \(magenta(" |  \\/  | ___  _ __   __ _  __| |"))
            \(magenta(" | |\\/| |/ _ \\| '_ \\ / _` |/ _` |"))
            \(magenta(" | |  | | (_) | | | | (_| | (_| |"))
            \(magenta(" |_|  |_|\\___/|_| |_|\\__,_|\\__,_|"))
            """
        print("\n" + logo + "\n")
        print(dim("  AI Assistant v1.0.0"))
        print("")
    }

    // MARK: - Markdown Rendering

    public static func renderMarkdown(_ text: String) -> String {
        // Very basic Markdown rendering for CLI
        var output = text

        // Bold (**text**)
        // regex: \*\*(.*?)\*\*
        // Note: Simple replacement, doesn't handle nested well but sufficient for CLI
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*", options: []) {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output, options: [], range: range, withTemplate: "\(boldCode)$1\(reset)")
        }

        // Code (`text`)
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output, options: [], range: range, withTemplate: "\(cyanCode)$1\(reset)")
        }

        return output
    }

    // MARK: - Chat UI

    public static func printWelcome() {
        printLogo()
        print(dim("Type /help for available commands, /quit to exit"))
        print("")
    }

    public static func printPrompt(workspace: String? = nil) {
        let wsPart = workspace != nil ? "[\(workspace!)] " : ""
        print("\n\(green(wsPart))\(cyan("monad")) \(bold(">")) ", terminator: "")
        fflush(stdout)
    }

    public static func printAssistantStart() {
        print("\(magenta("Assistant:")) ", terminator: "")
        fflush(stdout)
    }

    // MARK: - Formatting

    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Legacy / Simple Status

    public static func printLoading(_ message: String) {
        print("\(yellow("⏳")) \(message)")
    }

    public static func printDone(_ message: String) {
        print("\(green("✅")) \(message)")
    }
}
