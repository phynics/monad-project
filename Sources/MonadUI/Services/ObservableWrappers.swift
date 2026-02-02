import Foundation
import MonadCore
import Observation
import SwiftUI

/// UI-friendly wrapper for LLMService
@MainActor
@Observable
public final class LLMManager {
    public private(set) var isConfigured: Bool = false
    public private(set) var configuration: LLMConfiguration = .openAI
    
    private let service: LLMService
    
    public init(service: LLMService) {
        self.service = service
        Task {
            await refresh()
        }
    }
    
    public func refresh() async {
        let configured = await service.isConfigured
        let config = await service.configuration
        await MainActor.run {
            self.isConfigured = configured
            self.configuration = config
        }
    }
    
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        try await service.updateConfiguration(config)
        await refresh()
    }
    
    public func clearConfiguration() async {
        await service.clearConfiguration()
        await refresh()
    }
    
    public func restoreFromBackup() async throws {
        try await service.restoreFromBackup()
        await refresh()
    }
    
    public func exportConfiguration() async throws -> Data {
        return try await service.exportConfiguration()
    }
    
    public func importConfiguration(from data: Data) async throws {
        try await service.importConfiguration(from: data)
        await refresh()
    }
}

/// UI-friendly wrapper for DocumentManager
@MainActor
@Observable
public final class DocumentUIManager {
    public private(set) var documents: [DocumentContext] = []
    
    private let manager: DocumentManager
    
    public init(manager: DocumentManager) {
        self.manager = manager
        Task {
            await refresh()
        }
    }
    
    public func refresh() async {
        let docs = await manager.getAllDocuments()
        await MainActor.run {
            self.documents = docs
        }
    }
    
    public func togglePin(path: String) async {
        await manager.togglePin(path: path)
        await refresh()
    }
    
    public func unloadDocument(path: String) async {
        await manager.unloadDocument(path: path)
        await refresh()
    }
}

/// UI-friendly wrapper for SessionToolManager
@MainActor
@Observable
public final class ToolUIManager {
    public private(set) var enabledTools: Set<String> = []
    public private(set) var availableTools: [any MonadCore.Tool] = []
    
    private let manager: SessionToolManager
    
    public init(manager: SessionToolManager) {
        self.manager = manager
        Task {
            await refresh()
        }
    }
    
    public func refresh() async {
        let enabled = await manager.enabledTools
        let available = await manager.getAvailableTools()
        await MainActor.run {
            self.enabledTools = enabled
            self.availableTools = available
        }
    }
    
    public func toggleTool(_ toolId: String) async {
        await manager.toggleTool(toolId)
        await refresh()
    }
}