import MonadShared
import ArgumentParser
import Foundation
import MonadClient

struct ClientOptions: ParsableArguments {
    @Option(name: .long, help: "Server URL (auto-detects if omitted)")
    var server: String?

    @Option(name: .long, help: "API key")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose logging")
    var verbose: Bool = false

    func toConfiguration() -> ClientConfiguration {
        // Since this is synchronous, we cannot await autoDetect easily here if we want to return config immediately.
        // However, ClientConfiguration.fromEnvironment() is sync.
        // autoDetect is async.
        // MonadClient init takes config.

        // If we want auto-detect, we should probably do it async in the command run.
        // But for common usage, let's use sync fallback or environment.
        // To support async auto-detect, we might need a helper method that returns async.

        let envConfig = ClientConfiguration.fromEnvironment()

        let baseURL: URL
        if let serverUrl = server {
            baseURL = URL(string: serverUrl) ?? envConfig.baseURL
        } else {
            baseURL = envConfig.baseURL
        }

        // Read client ID from identity file
        let identity = RegistrationManager.shared.getIdentity()

        return ClientConfiguration(
            baseURL: baseURL,
            apiKey: apiKey ?? envConfig.apiKey,
            clientId: identity?.clientId,
            timeout: envConfig.timeout,
            verbose: verbose || envConfig.verbose
        )
    }
}
