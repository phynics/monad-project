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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".monad")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("identity.json")
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
