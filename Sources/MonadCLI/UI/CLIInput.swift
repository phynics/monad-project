import Foundation

enum CLIInput {
    static func readLine(prompt: String = "", default defaultValue: String? = nil) -> String? {
        let reader = LineReader(prompt: prompt)
        guard let input = reader.readLine(prompt: prompt, completion: nil) else {
            return nil
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let defaultValue {
            return defaultValue
        }
        return trimmed
    }

    static func readConfirmation(prompt: String, default defaultChoice: Bool) -> Bool? {
        let defaultValue = defaultChoice ? "y" : "n"
        guard let response = readLine(prompt: prompt, default: defaultValue)?.lowercased() else {
            return nil
        }
        return isAffirmative(response)
    }

    static func readInt(prompt: String, min: Int, max: Int) -> Int? {
        while true {
            guard let input = readLine(prompt: prompt) else {
                return nil
            }
            if let value = Int(input), value >= min, value <= max {
                return value
            }
            TerminalUI.printError("Invalid selection.")
        }
    }

    static func readMultiline(prompt: String, terminatorHint: String? = nil) -> MultilineResult {
        print(prompt)
        if let terminatorHint, !terminatorHint.isEmpty {
            print(TerminalUI.dim(terminatorHint))
        }

        var lines: [String] = []
        while true {
            guard let line = readLine(prompt: "") else {
                return .cancelled
            }
            if line.isEmpty {
                return .submitted(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            }
            lines.append(line)
        }
    }

    static func waitForEnter(prompt: String) -> Bool {
        readLine(prompt: prompt, default: "") != nil
    }

    static func isAffirmative(_ response: String) -> Bool {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "y" || normalized == "yes"
    }

    enum MultilineResult {
        case submitted(String)
        case cancelled
    }
}
