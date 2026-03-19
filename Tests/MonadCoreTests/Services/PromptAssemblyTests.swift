import Foundation
import MonadCore
import MonadPrompt
import MonadShared
import Testing

@Suite("PromptAssembly")
struct PromptAssemblyTests {

    // MARK: - Helpers

    private func makeRequest(userQuery: String = "hello") -> LLMPromptRequest {
        LLMPromptRequest(
            userQuery: userQuery,
            chatHistory: [],
            tools: [],
            workspaces: [],
            primaryWorkspace: nil,
            clientName: nil
        )
    }

    // MARK: - Mock Section

    struct MockSection: ContextSection, Sendable {
        let id: String
        let priority: Int = 10
        let estimatedTokens: Int = 10
        let content: String

        init(id: String, content: String = "test content") {
            self.id = id
            self.content = content
        }

        func render() async -> String? {
            content
        }
    }

    // MARK: - PromptAssemblyContext Tests

    @Test("PromptAssemblyContext holds properties")
    func contextHoldsProperties() async {
        let request = makeRequest(userQuery: "custom query")
        let agent = AgentInstance(id: UUID(), name: "TestAgent", description: "desc", privateTimelineId: UUID())
        let timeline = Timeline(id: UUID(), title: "TestTimeline")
        let ext = [MockSection(id: "ext")]

        let context = PromptAssemblyContext(
            request: request,
            agentInstance: agent,
            timeline: timeline,
            extensionSections: ext
        )

        #expect(await context.request.userQuery == "custom query")
        #expect(await context.agentInstance?.name == "TestAgent")
        #expect(await context.timeline?.title == "TestTimeline")
        #expect(await context.extensionSections.count == 1)
    }

    @Test("PromptAssemblyContext appends sections")
    func contextAppendsSections() async {
        let request = makeRequest()
        let context = PromptAssemblyContext(request: request)

        await context.append(MockSection(id: "s1"))
        await context.append([MockSection(id: "s2"), MockSection(id: "s3")])

        let sections = await context.sections
        #expect(sections.count == 3)
        #expect(sections[0].id == "s1")
        #expect(sections[1].id == "s2")
        #expect(sections[2].id == "s3")
    }

    // MARK: - PromptAssemblyBuilder Tests

    @Test("PromptAssemblyBuilder composes sections")
    func builderComposesSections() {
        @PromptAssemblyBuilder
        func build() -> [any ContextSection] {
            MockSection(id: "s1")
            [MockSection(id: "s2"), MockSection(id: "s3")]
            if true {
                MockSection(id: "s4")
            }
        }

        let sections = build()
        #expect(sections.count == 4)
        #expect(sections.map { $0.id } == ["s1", "s2", "s3", "s4"])
    }
}
