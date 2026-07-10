import Foundation
@testable import MonadCLICore
import MonadShared
import PKShared
import Testing

@Suite struct ConfigurationPreflightTests {
    @Test("invalid config requires setup even when AI status is ok")
    func invalidConfig_requiresSetup() {
        let config = LLMConfiguration(activeProvider: .openAI)
        let status = StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 1,
            components: [
                "ai_provider": ComponentStatus(status: .ok)
            ]
        )

        #expect(ConfigurationPreflight.evaluate(config: config, status: status) == .needsSetup)
    }

    @Test("degraded AI status requires setup even when stored config is valid")
    func degradedAI_requiresSetup() {
        var config = LLMConfiguration(activeProvider: .openRouter)
        config.providers[.openRouter]?.apiKey = "sk-test"

        let status = StatusResponse(
            status: .degraded,
            version: "1.0.0",
            uptime: 1,
            components: [
                "ai_provider": ComponentStatus(status: .degraded)
            ]
        )

        #expect(ConfigurationPreflight.evaluate(config: config, status: status) == .needsSetup)
    }

    @Test("valid config with healthy AI is ready")
    func healthyAI_isReady() {
        var config = LLMConfiguration(activeProvider: .openRouter)
        config.providers[.openRouter]?.apiKey = "sk-test"

        let status = StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 1,
            components: [
                "ai_provider": ComponentStatus(status: .ok)
            ]
        )

        #expect(ConfigurationPreflight.evaluate(config: config, status: status) == .ready)
    }
}
