import Foundation

public protocol ClientConnectionManagerProtocol: Sendable {
    func send<T: Codable & Sendable>(
        method: String,
        params: AnyCodable?,
        expecting: T.Type,
        to clientId: UUID
    ) async throws -> T
    
    func isConnected(clientId: UUID) async -> Bool
}
