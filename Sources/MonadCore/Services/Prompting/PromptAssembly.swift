import Foundation
import MonadPrompt
import MonadShared

/// Manages prompt assembly state. Pipeline-ready.
public actor PromptAssemblyContext: Sendable {
    public let request: LLMPromptRequest
    public let agentInstance: AgentInstance?
    public let timeline: Timeline?
    public let extensionSections: [any ContextSection]
    public private(set) var sections: [any ContextSection] = []

    public init(
        request: LLMPromptRequest,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil,
        extensionSections: [any ContextSection] = []
    ) {
        self.request = request
        self.agentInstance = agentInstance
        self.timeline = timeline
        self.extensionSections = extensionSections
    }

    public func append(_ section: any ContextSection) {
        sections.append(section)
    }

    public func append(_ sections: [any ContextSection]) {
        self.sections.append(contentsOf: sections)
    }
}

/// DSL for composing prompt assembly stages.
@resultBuilder
public struct PromptAssemblyBuilder {
    public static func buildExpression(_ expression: any ContextSection) -> [any ContextSection] { [expression] }
    public static func buildExpression(_ expression: [any ContextSection]) -> [any ContextSection] { expression }
    public static func buildBlock(_ components: [any ContextSection]...) -> [any ContextSection] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [any ContextSection]?) -> [any ContextSection] { component ?? [] }
    public static func buildEither(first component: [any ContextSection]) -> [any ContextSection] { component }
    public static func buildEither(second component: [any ContextSection]) -> [any ContextSection] { component }
    public static func buildArray(_ components: [[any ContextSection]]) -> [any ContextSection] { components.flatMap { $0 } }
}
