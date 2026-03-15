import Foundation
import Logging
import MonadClient
import MonadShared

struct StoredIdentity: Codable {
    let clientId: UUID
    let clientName: String
    let hostname: String
    let shellWorkspaceId: UUID
    let shellWorkspaceURI: String
}

struct RegistrationManager {
    static let shared = RegistrationManager()
    private let logger = Logger.module(named: "registration")

    private var storageURL: URL {
        let fileManager = FileManager.default
        let appName = "Monad"
        let filename = "identity.json"

        #if os(macOS)
            // ~/Library/Application Support/Monad/identity.json
            if let appSupport = fileManager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first {
                let dir = appSupport.appendingPathComponent(appName)
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir.appendingPathComponent(filename)
            }
        #elseif os(Linux)
            // XDG_CONFIG_HOME or ~/.config/monad/identity.json
            let env = ProcessInfo.processInfo.environment
            let configHome: URL
            if let xdgConfig = env["XDG_CONFIG_HOME"] {
                configHome = URL(fileURLWithPath: xdgConfig)
            } else {
                configHome = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                    ".config"
                )
            }

            let dir = configHome.appendingPathComponent(appName.lowercased())
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(filename)
        #endif

        // Fallback
        let dir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".monad")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    func getIdentity() -> StoredIdentity? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        do {
            return try JSONDecoder().decode(StoredIdentity.self, from: data)
        } catch {
            logger.error("Failed to decode stored identity: \(error)")
            return nil
        }
    }

    func saveIdentity(_ identity: StoredIdentity) throws {
        do {
            let data = try JSONEncoder().encode(identity)
            try data.write(to: storageURL)
            logger.debug("Successfully saved identity to \(storageURL.path)")
        } catch {
            logger.error("Failed to save identity to \(storageURL.path): \(error)")
            throw error
        }
    }

    @discardableResult
    func ensureRegistered(client: MonadClient) async throws -> StoredIdentity {
        let tools = ClientConstants.readOnlyToolReferences

        if let existing = getIdentity() {
            do {
                logger.debug("Existing identity found for client \(existing.clientId). Syncing tools...")
                // Always sync tools on connect to keep the server's DB current
                // (tool set may have changed since last registration)
                try await client.workspace.syncWorkspaceTools(tools, workspaceId: existing.shellWorkspaceId)
                return existing
            } catch {
                // swiftlint:disable:next line_length
                logger.warning("Sync failed for workspace \(existing.shellWorkspaceId): \(error). Clearing identity for re-registration.")
                // Workspace no longer exists (e.g. database was reset). Clear the cached identity
                // so we fall through and register fresh below.
                try? FileManager.default.removeItem(at: storageURL)
            }
        }

        // First-time registration
        logger.info("Registering new client with server...")
        let hostname = ProcessInfo.processInfo.hostName
        let displayName = NSUserName()
        let platform = "macos" // Detect dynamically if needed

        let response = try await client.registerClient(
            hostname: hostname,
            displayName: displayName,
            platform: platform,
            tools: tools
        )

        let identity = StoredIdentity(
            clientId: response.client.id,
            clientName: response.client.displayName,
            hostname: response.client.hostname,
            shellWorkspaceId: response.defaultWorkspace.id,
            shellWorkspaceURI: response.defaultWorkspace.uri.description
        )

        try saveIdentity(identity)
        logger.info("Client successfully registered: \(identity.clientId)")
        return identity
    }
}
