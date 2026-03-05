@testable import MonadCore
import Foundation
@testable import MonadShared
@testable import MonadServer

public final class MockClientStore: ClientStoreProtocol, @unchecked Sendable {
    public var clients: [ClientIdentity] = []

    public init() {}

    public func saveClient(_ client: ClientIdentity) async throws {
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
        } else {
            clients.append(client)
        }
    }

    public func fetchClient(id: UUID) async throws -> ClientIdentity? {
        return clients.first(where: { $0.id == id })
    }

    public func fetchAllClients() async throws -> [ClientIdentity] {
        return clients
    }

    public func deleteClient(id: UUID) async throws -> Bool {
        let countBefore = clients.count
        clients.removeAll(where: { $0.id == id })
        return countBefore > clients.count
    }
}
