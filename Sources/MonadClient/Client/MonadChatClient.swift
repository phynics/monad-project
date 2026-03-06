import Foundation
import MonadShared

/// Domain-specific client for Chat, Session, Memory, and MSAgent operations
public struct MonadChatClient: Sendable {
    public let client: MonadClient
    
    public init(client: MonadClient) {
        self.client = client
    }
}
