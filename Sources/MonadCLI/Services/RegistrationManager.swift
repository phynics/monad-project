import Foundation
import MonadClient
import MonadCore

struct StoredIdentity: Codable {
    let clientId: UUID
    let clientName: String
    let hostname: String
    let shellWorkspaceId: UUID
    let shellWorkspaceURI: String
}

struct RegistrationManager {
    static let shared = RegistrationManager()

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
                    ".config")
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
        return try? JSONDecoder().decode(StoredIdentity.self, from: data)
    }

    func saveIdentity(_ identity: StoredIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        try data.write(to: storageURL)
    }

    func ensureRegistered(client: MonadClient) async throws -> StoredIdentity {
        if let existing = getIdentity() {
            // Verify with server? For now assume valid if we have it.
            return existing
        }

        // Register
        let hostname = ProcessInfo.processInfo.hostName
        let displayName = NSUserName()
        let platform = "macos"  // Detect dynamically if needed

        // Define client tools
        let tools: [ToolReference] = [
            .custom(definition: WorkspaceToolDefinition(from: AskAttachPWDTool()))
        ]

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
        return identity
    }
}
