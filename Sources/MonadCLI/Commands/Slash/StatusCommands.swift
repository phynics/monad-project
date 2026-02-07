import Foundation
import MonadClient

struct StatusCommand: SlashCommand {
    let name = "status"
    let aliases: [String] = []
    let description = "Show server and component status"
    let category: String? = "General"

    func run(args: [String], context: ChatContext) async throws {
        TerminalUI.printLoading("Fetching server status...")
        
        do {
            let status = try await context.client.getStatus()
            
            print("")
            print(TerminalUI.bold("Monad Server Status"))
            print("─────────────────────────────────────────")
            
            let overallStatus = formatStatus(status.status)
            print("Overall:  \(overallStatus)")
            print("Version:  \(status.version)")
            
            // Format uptime if > 0
            if status.uptime > 0 {
                print("Uptime:   \(formatDuration(status.uptime))")
            }
            
            print("\n" + TerminalUI.bold("Components:"))
            for (name, component) in status.components.sorted(by: { $0.key < $1.key }) {
                let compStatus = formatStatus(component.status)
                let namePadded = name.padding(toLength: 12, withPad: " ", startingAt: 0)
                print("  \(namePadded) \(compStatus)")
                
                if let details = component.details, !details.isEmpty {
                    for (key, value) in details.sorted(by: { $0.key < $1.key }) {
                        print("    \(TerminalUI.dim("\(key): \(value)"))")
                    }
                }
            }
            print("─────────────────────────────────────────")
            print("")
            
        } catch {
            TerminalUI.printError("Failed to fetch status: \(error.localizedDescription)")
        }
    }
    
    private func formatStatus(_ status: HealthStatus) -> String {
        switch status {
        case .ok:
            return TerminalUI.green("ONLINE")
        case .degraded:
            return TerminalUI.yellow("DEGRADED")
        case .down:
            return TerminalUI.red("OFFLINE")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "\(duration)s"
    }
}
