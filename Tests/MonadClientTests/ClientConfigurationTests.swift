import Foundation
@testable import MonadClient
import Testing

struct ClientConfigurationTests {
    @Test("explicit URL takes precedence over environment and discovery")
    func explicitURLPrecedence() async throws {
        let explicitURL = try #require(URL(string: "http://explicit.example:9000"))
        let environmentURL = try #require(URL(string: "http://environment.example:9001"))

        let configuration = await ClientConfiguration.autoDetect(
            explicitURL: explicitURL,
            environment: ["MONAD_SERVER_URL": environmentURL.absoluteString],
            discover: Self.unexpectedDiscovery
        )

        #expect(configuration.baseURL == explicitURL)
    }

    @Test("environment URL takes precedence over discovery")
    func environmentURLPrecedence() async throws {
        let environmentURL = try #require(URL(string: "http://environment.example:9001"))

        let configuration = await ClientConfiguration.autoDetect(
            environment: ["MONAD_SERVER_URL": environmentURL.absoluteString],
            discover: Self.unexpectedDiscovery
        )

        #expect(configuration.baseURL == environmentURL)
    }

    private static func unexpectedDiscovery(_: TimeInterval) async -> URL? {
        Issue.record("Discovery must not run when a configured URL is available")
        return nil
    }
}
