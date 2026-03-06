import Foundation
import MonadClient
import MonadShared

extension ChatREPL {
    func printToolAttempt(name: String, argsJSON: String, reference: ToolReference) {
        let location: String
        switch reference {
        case .known: location = "server"
        case .custom: location = "local"
        }
        let paramsStr = formatToolArgs(argsJSON)
        let header = TerminalUI.blue("⟩ \(name)")
        let params = paramsStr.isEmpty ? "" : "  " + TerminalUI.dim(paramsStr)
        let loc = "  " + TerminalUI.dim("[\(location)]")
        print(header + params + loc)
    }

    func printToolResult(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print(TerminalUI.dim("  ✓ (no output)"))
            return
        }
        let lines = trimmed.components(separatedBy: .newlines)
        let maxLines = 8
        for line in lines.prefix(maxLines) {
            let display = line.count > 120 ? String(line.prefix(120)) + "…" : line
            print(TerminalUI.dim("  \(display)"))
        }
        if lines.count > maxLines {
            print(TerminalUI.dim("  ↳ +\(lines.count - maxLines) more lines"))
        }
    }

    func formatToolArgs(_ json: String) -> String {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !dict.isEmpty
        else { return "" }
        let parts = dict.keys.sorted().map { key -> String in
            let value = String(describing: dict[key]!)
            let truncated = value.count > 60 ? String(value.prefix(60)) + "…" : value
            return "\(key)=\(truncated)"
        }
        let joined = parts.joined(separator: "  ")
        return joined.count > 120 ? String(joined.prefix(120)) + "…" : joined
    }

    func updateDebugSnapshot(_ data: Data) {
        lastDebugSnapshot = try? SerializationUtils.jsonDecoder.decode(DebugSnapshot.self, from: data)
    }
}
