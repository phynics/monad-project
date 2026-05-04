import MonadShared
import PKShared

enum ConfigurationPreflight: Equatable {
    case ready
    case needsSetup

    static func evaluate(config: LLMConfiguration, status: StatusResponse) -> Self {
        guard config.isValid else {
            return .needsSetup
        }

        let aiStatus = status.components["ai_provider"]?.status
        guard aiStatus == .ok else {
            return .needsSetup
        }

        return .ready
    }
}
