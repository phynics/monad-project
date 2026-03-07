import Foundation
import MonadClient
import MonadShared

// Needed for fflush
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The main Request-Eval-Print Loop for the Chat Interface
actor ChatREPL: ChatREPLController {
    let client: MonadClient
    var timeline: Timeline
    var running = true
    var selectedWorkspaceId: UUID?
    var lastDebugSnapshot: DebugSnapshot?
    var lastServerStatus: Bool = true

    /// The currently attached agent instance (nil = no agent attached).
    var currentAgent: AgentInstance?

    // Slash Command Registry
    let registry = SlashCommandRegistry()
    let lineReader = LineReader()

    /// The currently active generation task
    var currentGenerationTask: Task<Void, Never>?
    var escapeMonitorTask: Task<Void, Never>?
    var signalSource: DispatchSourceSignal?

    /// Track consecutive Ctrl-C presses for force-exit
    var lastSigintTime: Date?

    init(client: MonadClient, timeline: Timeline, agent: AgentInstance? = nil) {
        self.client = client
        self.timeline = timeline
        currentAgent = agent
    }
}
