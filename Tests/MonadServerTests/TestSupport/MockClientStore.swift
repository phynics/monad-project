@testable import PositronicKit
import Foundation
@testable import PKShared
import MonadShared
@testable import MonadServer

public final class MockClientStore: RequestOriginStoreProtocol, @unchecked Sendable {
    public var origins: [RequestOriginIdentity] = []

    public init() {}

    public func saveOrigin(_ origin: RequestOriginIdentity) async throws {
        if let index = origins.firstIndex(where: { $0.id == origin.id }) {
            origins[index] = origin
        } else {
            origins.append(origin)
        }
    }

    public func fetchOrigin(id: UUID) async throws -> RequestOriginIdentity? {
        return origins.first(where: { $0.id == id })
    }

    public func fetchAllOrigins() async throws -> [RequestOriginIdentity] {
        return origins
    }

    public func deleteOrigin(id: UUID) async throws -> Bool {
        let countBefore = origins.count
        origins.removeAll(where: { $0.id == id })
        return countBefore > origins.count
    }

    public func fetchOriginTools(originId: UUID) async throws -> [ToolReference] {
        _ = originId
        return []
    }
}
