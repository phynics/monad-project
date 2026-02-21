import MonadShared
import Foundation
import Logging
import ServiceLifecycle
import Dependencies

/// Service that cleans up orphaned workspaces
public final class OrphanCleanupService: Service, @unchecked Sendable {
    @Dependency(\.persistenceService) private var persistenceService
    
    private let workspaceRoot: URL
    private let logger = Logger(label: "com.monad.orphan-cleanup")

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    /// Run the cleanup loop
    public func run() async throws {
        logger.info("OrphanCleanupService started")
        // Run initial cleanup
        await cleanup()
        
        await cancelWhenGracefulShutdown {
            // Then run periodically (every 24 hours)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 86400 * 1_000_000_000) // 24 hours
                    await self.cleanup()
                } catch {
                    if error is CancellationError {
                        self.logger.info("OrphanCleanupService shutting down gracefully")
                        break
                    }
                    self.logger.error("Error in OrphanCleanupService loop: \(error)")
                }
            }
        }
        logger.info("OrphanCleanupService stopped")
    }

    private func cleanup() async {
        logger.info("Starting orphaned workspace cleanup...")
        do {
            let workspaces = try await persistenceService.fetchAllWorkspaces()
            let sessions = try await persistenceService.fetchAllSessions(includeArchived: true)
            
            var referencedIds: Set<UUID> = []
            
            // Collect all referenced IDs
            for session in sessions {
                if let pid = session.primaryWorkspaceId {
                    referencedIds.insert(pid)
                }
                for aid in session.attachedWorkspaces {
                    referencedIds.insert(aid)
                }
            }
            
            var deletedCount = 0
            for ws in workspaces {
                if !referencedIds.contains(ws.id) {
                    // Check if it's safe to delete (is it in the Monad Workspaces dir?)
                    if let rootPath = ws.rootPath, 
                       rootPath.hasPrefix(workspaceRoot.path) || rootPath.contains("/.monad/workspaces/") || rootPath.contains("/Monad/Workspaces/") {
                        
                        // Delete DB Record
                        try await persistenceService.deleteWorkspace(id: ws.id)
                        
                        // Delete Filesystem
                        if FileManager.default.fileExists(atPath: rootPath) {
                            try? FileManager.default.removeItem(atPath: rootPath)
                        }
                        deletedCount += 1
                        logger.info("Deleted orphaned workspace: \(ws.id) at \(rootPath)")
                    } else {
                        logger.warning("Skipping cleanup of user-managed workspace: \(ws.id) at \(ws.rootPath ?? "nil")")
                    }
                }
            }
            
            if deletedCount > 0 {
                logger.info("Cleanup complete. Removed \(deletedCount) orphaned workspaces.")
            } else {
                logger.info("Cleanup complete. No orphaned workspaces found.")
            }
        } catch {
            logger.error("Failed to run orphan cleanup: \(error)")
        }
    }
}
