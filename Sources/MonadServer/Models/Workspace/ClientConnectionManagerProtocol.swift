import Foundation
import PKShared

public protocol ClientConnectionManagerProtocol: Sendable {
    func isConnected(clientId: UUID) async -> Bool
    func send<T: Codable & Sendable>(
        method: String,
        params: AnyCodable?,
        expecting: T.Type,
        to clientId: UUID
    ) async throws -> T
}
