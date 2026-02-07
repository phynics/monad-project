import ArgumentParser
import Foundation
import MonadClient

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show server and component status"
    )

    @Option(name: .long, help: "Server URL")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    func run() async throws {
        // Load local config
        let localConfig = LocalConfigManager.shared.getConfig()

        // Determine explicit URL (Flag > Local Config)
        let explicitURL: URL?
        if let serverFlag = server {
            explicitURL = URL(string: serverFlag)
        } else {
            explicitURL = localConfig.serverURL.flatMap { URL(string: $0) }
        }

        let config = await ClientConfiguration.autoDetect(
            explicitURL: explicitURL,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"]
                ?? localConfig.apiKey,
            verbose: verbose
        )

        let client = MonadClient(configuration: config)
        
        TerminalUI.printLoading("Fetching server status from \(config.baseURL.absoluteString)...")
        
        do {
            let status = try await client.getStatus()
            
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
            if verbose {
                print("Error details: \(error)")
            }
            throw ExitCode.failure
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
