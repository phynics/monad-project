import Foundation
import MonadShared
@testable import MonadCLICore
import PKShared
import Testing

@Suite struct CLITimelineCatalogTests {
    @Test("blank peek query uses current agent private timeline")
    func resolvePeekTarget_blankUsesCurrentAgentPrivateTimeline() {
        let privateTimelineId = UUID()
        let agent = AgentInstance(
            name: "Assistant",
            description: "Primary agent",
            privateTimelineId: privateTimelineId
        )

        let result = CLITimelineCatalog.resolvePeekTarget(
            query: nil,
            publicTimelines: [],
            currentAgent: agent
        )

        guard case let .privateTimeline(id) = result else {
            Issue.record("Expected private timeline resolution")
            return
        }

        #expect(id == privateTimelineId)
    }

    @Test("private peek keyword uses current agent private timeline")
    func resolvePeekTarget_privateKeywordUsesCurrentAgentPrivateTimeline() {
        let privateTimelineId = UUID()
        let agent = AgentInstance(
            name: "Assistant",
            description: "Primary agent",
            privateTimelineId: privateTimelineId
        )

        let result = CLITimelineCatalog.resolvePeekTarget(
            query: "private",
            publicTimelines: [],
            currentAgent: agent
        )

        guard case let .privateTimeline(id) = result else {
            Issue.record("Expected private timeline resolution")
            return
        }

        #expect(id == privateTimelineId)
    }

    @Test("numbered peek query resolves in public timeline order")
    func resolvePeekTarget_numberUsesSortedPublicTimelines() {
        let older = timeline(title: "Older", createdAt: Date(timeIntervalSince1970: 10))
        let newer = timeline(title: "Newer", createdAt: Date(timeIntervalSince1970: 20))

        let result = CLITimelineCatalog.resolvePeekTarget(
            query: "1",
            publicTimelines: [older, newer],
            currentAgent: nil
        )

        guard case let .publicTimeline(selected) = result else {
            Issue.record("Expected public timeline resolution")
            return
        }

        #expect(selected.id == newer.id)
    }

    @Test("title peek query resolves unique case-insensitive title match")
    func resolvePeekTarget_titleUsesCaseInsensitiveUniqueMatch() {
        let alpha = timeline(title: "Alpha")
        let beta = timeline(title: "Lazy Completed")

        let result = CLITimelineCatalog.resolvePeekTarget(
            query: "lazy completed",
            publicTimelines: [alpha, beta],
            currentAgent: nil
        )

        guard case let .publicTimeline(selected) = result else {
            Issue.record("Expected public timeline resolution")
            return
        }

        #expect(selected.id == beta.id)
    }

    @Test("title peek query returns ambiguous matches for disambiguation")
    func resolvePeekTarget_titleReturnsAmbiguousMatches() {
        let one = timeline(title: "Lazy Completed")
        let two = timeline(title: "Lazy Compiler")

        let result = CLITimelineCatalog.resolvePeekTarget(
            query: "lazy",
            publicTimelines: [one, two],
            currentAgent: nil
        )

        guard case let .ambiguous(matches) = result else {
            Issue.record("Expected ambiguous matches")
            return
        }

        #expect(matches.count == 2)
        #expect(Set(matches.map(\.id)) == Set([one.id, two.id]))
    }

    private func timeline(
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> TimelineResponse {
        TimelineResponse(
            id: UUID(),
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isArchived: false,
            workingDirectory: nil,
            attachedWorkspaceIds: [],
            attachedAgentInstanceId: nil
        )
    }
}
