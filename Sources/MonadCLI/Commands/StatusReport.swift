import Foundation
import MonadClient
import MonadShared
import PKShared

/// A snapshot of everything `monad status` reports, assembled independently of how each
/// piece of data was obtained. Building this from already-fetched data (rather than
/// fetching inline) keeps the reporting/formatting logic testable without a live server.
struct StatusReport: Equatable {
    enum ServerReachability: Equatable {
        case reachable(StatusResponse)
        case unreachable(message: String)
    }

    enum ConfigurationReadiness: Equatable {
        /// Provider configuration is valid and the AI provider component reported healthy.
        case ready
        /// Provider configuration is missing/invalid, or the provider is unreachable.
        case needsSetup(reason: String)
        /// Readiness could not be determined (e.g. the server itself is unreachable).
        case unknown(message: String)
    }

    let serverURL: String
    let apiKeyConfigured: Bool
    let reachability: ServerReachability
    let configuration: ConfigurationReadiness
}

enum StatusReportFormatter {
    private static let divider = "─────────────────────────────────────────"

    static func format(_ report: StatusReport) -> [String] {
        var lines: [String] = []

        lines.append(TerminalUI.bold("Monad Server Status"))
        lines.append(divider)
        lines.append("Server:   \(report.serverURL)")
        lines.append("API key:  \(apiKeyLine(report.apiKeyConfigured))")

        switch report.reachability {
        case let .reachable(status):
            appendReachable(status, to: &lines)
        case let .unreachable(message):
            appendUnreachable(message, to: &lines)
        }

        lines.append("")
        lines.append("Config:   \(configurationLine(report.configuration))")
        lines.append(divider)

        return lines
    }

    private static func apiKeyLine(_ configured: Bool) -> String {
        configured ? TerminalUI.green("configured") : TerminalUI.yellow("not set (public/local server?)")
    }

    private static func configurationLine(_ readiness: StatusReport.ConfigurationReadiness) -> String {
        switch readiness {
        case .ready:
            return "\(TerminalUI.green("ready")) — provider configured and reachable"
        case let .needsSetup(reason):
            return "\(TerminalUI.yellow("needs setup")) — \(reason)"
        case let .unknown(message):
            return "\(TerminalUI.dim("unknown")) — \(message)"
        }
    }

    private static func appendReachable(_ status: StatusResponse, to lines: inout [String]) {
        lines.append("Overall:  \(formatStatus(status.status))")
        lines.append("Version:  \(status.version)")

        if status.uptime > 0 {
            lines.append("Uptime:   \(formatDuration(status.uptime))")
        }

        lines.append("")
        lines.append(TerminalUI.bold("Components:"))
        for (name, component) in status.components.sorted(by: { $0.key < $1.key }) {
            let namePadded = name.padding(toLength: 12, withPad: " ", startingAt: 0)
            lines.append("  \(namePadded) \(formatStatus(component.status))")

            if let details = component.details, !details.isEmpty {
                for (key, value) in details.sorted(by: { $0.key < $1.key }) {
                    lines.append("    \(TerminalUI.dim("\(key): \(value)"))")
                }
            }
        }
    }

    private static func appendUnreachable(_ message: String, to lines: inout [String]) {
        lines.append("Overall:  \(TerminalUI.red("UNREACHABLE"))")
        lines.append("")
        lines.append(TerminalUI.dim(message))
        lines.append("")
        lines.append(TerminalUI.bold("Troubleshooting:"))
        lines.append("  1. `monad status` and `monad chat` never start a server themselves.")
        lines.append("     Start one first, in another terminal: \(TerminalUI.dim("monad server"))")
        lines.append("  2. Point at the right server: \(TerminalUI.dim("monad status --server <url>"))")
        lines.append("  3. Re-run with \(TerminalUI.dim("--verbose")) for the underlying error.")
    }

    private static func formatStatus(_ status: HealthStatus) -> String {
        switch status {
        case .ok:
            return TerminalUI.green("ONLINE")
        case .degraded:
            return TerminalUI.yellow("DEGRADED")
        case .down:
            return TerminalUI.red("OFFLINE")
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "\(duration)s"
    }
}
