import Foundation
import MonadClient
import MonadShared
@testable import MonadCLICore
import ArgumentParser
import Testing

@Suite struct CLICommandSupportTests {
    @Test("explicit server URL overrides local config")
    func resolvedServerURL_prefersExplicitValue() {
        let localConfig = LocalConfig(serverURL: "http://saved:8080")

        let resolvedURL = CLICommandSupport.resolvedServerURL(
            serverFlag: "http://explicit:8080",
            localConfig: localConfig
        )

        #expect(resolvedURL?.absoluteString == "http://explicit:8080")
    }

    @Test("local config server URL is used when no explicit server is provided")
    func resolvedServerURL_fallsBackToLocalConfig() {
        let localConfig = LocalConfig(serverURL: "http://saved:8080")

        let resolvedURL = CLICommandSupport.resolvedServerURL(
            serverFlag: nil,
            localConfig: localConfig
        )

        #expect(resolvedURL?.absoluteString == "http://saved:8080")
    }

    @Test("explicit timeline ID returns the matching timeline")
    func resolveTimeline_prefersExplicitTimeline() async throws {
        let targetTimeline = TimelineResponse(id: UUID(), title: "Explicit")
        let helper = CLICommandSupport(localConfig: LocalConfig(), reportError: { _ in })

        let resolvedTimeline = try await helper.resolveTimeline(
            explicitTimelineID: targetTimeline.id.uuidString,
            listTimelines: { [targetTimeline] },
            createTimeline: { Issue.record("Should not create a new timeline"); return TimelineResponse(id: UUID(), title: nil) }
        )

        #expect(resolvedTimeline.id == targetTimeline.id)
    }

    @Test("last session ID returns the matching saved timeline")
    func resolveTimeline_usesLastSessionWhenAvailable() async throws {
        let savedTimeline = TimelineResponse(id: UUID(), title: "Saved")
        let helper = CLICommandSupport(
            localConfig: LocalConfig(lastSessionId: savedTimeline.id.uuidString),
            reportError: { _ in }
        )

        let resolvedTimeline = try await helper.resolveTimeline(
            explicitTimelineID: nil,
            listTimelines: { [savedTimeline] },
            createTimeline: { Issue.record("Should not create a new timeline"); return TimelineResponse(id: UUID(), title: nil) }
        )

        #expect(resolvedTimeline.id == savedTimeline.id)
    }

    @Test("missing explicit timeline ID fails instead of creating a new one")
    func resolveTimeline_missingExplicitTimelineThrows() async {
        let helper = CLICommandSupport(localConfig: LocalConfig(), reportError: { _ in })

        do {
            _ = try await helper.resolveTimeline(
                explicitTimelineID: UUID().uuidString,
                listTimelines: { [] },
                createTimeline: { TimelineResponse(id: UUID(), title: nil) }
            )
            Issue.record("Expected explicit missing timeline to fail")
        } catch is ExitCode {
        } catch {
            Issue.record("Expected ExitCode failure, got \(error)")
        }
    }

    @Test("creates a new timeline when no reusable timeline exists")
    func resolveTimeline_createsTimelineAsFallback() async throws {
        let createdTimeline = TimelineResponse(id: UUID(), title: "Created")
        let helper = CLICommandSupport(
            localConfig: LocalConfig(lastSessionId: UUID().uuidString),
            reportError: { _ in }
        )

        let resolvedTimeline = try await helper.resolveTimeline(
            explicitTimelineID: nil,
            listTimelines: { [] },
            createTimeline: { createdTimeline }
        )

        #expect(resolvedTimeline.id == createdTimeline.id)
    }
}
