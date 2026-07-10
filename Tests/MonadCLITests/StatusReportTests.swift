import Foundation
@testable import MonadCLICore
import MonadShared
import PKShared
import Testing

struct StatusReportTests {
    @Test("valid config with healthy ai_provider is ready")
    func classifyConfiguration_readyWhenValidAndHealthy() {
        var config = LLMConfiguration.default
        config.activeProvider = .openAI
        config.modelName = "gpt-test"
        config.apiKey = "sk-test"

        let status = StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 10,
            components: ["ai_provider": ComponentStatus(status: .ok, details: nil)]
        )

        let readiness = Status.classifyConfiguration(config: config, status: status)

        #expect(readiness == .ready)
    }

    @Test("invalid config (missing API key) needs setup")
    func classifyConfiguration_needsSetupWhenInvalid() {
        var config = LLMConfiguration.default
        config.activeProvider = .openAI
        config.modelName = ""
        config.apiKey = ""

        let status = StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 10,
            components: ["ai_provider": ComponentStatus(status: .ok, details: nil)]
        )

        let readiness = Status.classifyConfiguration(config: config, status: status)

        guard case .needsSetup = readiness else {
            Issue.record("Expected .needsSetup, got \(readiness)")
            return
        }
    }

    @Test("valid config but degraded ai_provider component needs setup")
    func classifyConfiguration_needsSetupWhenProviderUnhealthy() {
        var config = LLMConfiguration.default
        config.activeProvider = .openAI
        config.modelName = "gpt-test"
        config.apiKey = "sk-test"

        let status = StatusResponse(
            status: .degraded,
            version: "1.0.0",
            uptime: 10,
            components: ["ai_provider": ComponentStatus(status: .down, details: nil)]
        )

        let readiness = Status.classifyConfiguration(config: config, status: status)

        guard case .needsSetup = readiness else {
            Issue.record("Expected .needsSetup, got \(readiness)")
            return
        }
    }

    @Test("formatter reports UNREACHABLE and troubleshooting steps when server can't be reached")
    func formatter_showsTroubleshootingWhenUnreachable() {
        let report = StatusReport(
            serverURL: "http://127.0.0.1:8080",
            apiKeyConfigured: false,
            reachability: .unreachable(message: "Connection refused"),
            configuration: .unknown(message: "server unreachable")
        )

        let lines = StatusReportFormatter.format(report)
        let joined = lines.joined(separator: "\n")

        #expect(joined.contains("UNREACHABLE"))
        #expect(joined.contains("monad server"))
        #expect(joined.contains("Connection refused"))
    }

    @Test("formatter reports component details when reachable")
    func formatter_showsComponentsWhenReachable() {
        let status = StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 5,
            components: ["database": ComponentStatus(status: .ok, details: ["path": "/tmp/db"])]
        )
        let report = StatusReport(
            serverURL: "http://127.0.0.1:8080",
            apiKeyConfigured: true,
            reachability: .reachable(status),
            configuration: .ready
        )

        let lines = StatusReportFormatter.format(report)
        let joined = lines.joined(separator: "\n")

        #expect(joined.contains("database"))
        #expect(joined.contains("path: /tmp/db"))
        #expect(joined.contains("ready"))
    }
}
