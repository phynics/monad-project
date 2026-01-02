import Foundation
import Observation
import MonadCore

/// UI View Model wrapper for the Core LLMService
@MainActor
@Observable
public final class LLMServiceViewModel {
    public var configuration: LLMConfiguration = .openAI
    public var isConfigured: Bool = false

    // We keep a reference to the core actor service
    public let coreService: LLMService

    public init(coreService: LLMService) {
        self.coreService = coreService

        // Initial sync (will happen asynchronously)
        Task {
            await coreService.initialize()
            await syncState()
        }
    }

    /// Syncs local observable state with the core actor state
    private func syncState() async {
        self.configuration = await coreService.configuration
        self.isConfigured = await coreService.isConfigured
    }

    // MARK: - Proxy Methods

    public func loadConfiguration() async {
        await coreService.loadConfiguration()
        await syncState()
    }

    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        try await coreService.updateConfiguration(config)
        await syncState()
    }

    public func clearConfiguration() async {
        await coreService.clearConfiguration()
        await syncState()
    }

    public func restoreFromBackup() async throws {
        try await coreService.restoreFromBackup()
        await syncState()
    }

    public func exportConfiguration() async throws -> Data {
        try await coreService.exportConfiguration()
    }

    public func importConfiguration(from data: Data) async throws {
        try await coreService.importConfiguration(from: data)
        await syncState()
    }

    public func sendMessage(_ content: String) async throws -> String {
        try await coreService.sendMessage(content)
    }
}
