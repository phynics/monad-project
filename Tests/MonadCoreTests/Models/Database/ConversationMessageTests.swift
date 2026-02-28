import XCTest
@testable import MonadCore
import Foundation

final class ConversationMessageTests: XCTestCase {
    private func assertCodable<T: Codable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(value)
        _ = try decoder.decode(T.self, from: data)
    }
    
    func testConversationMessageCodable() throws {
        // Need to provide a realistic `Session` ID for foreign key in DB context
        let sessionId = UUID()
        let msg = ConversationMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: "Ping",
            timestamp: Date()
        )
        try assertCodable(msg)
    }
    
    func testToMessageConversion() throws {
        let uuid = UUID()
        let date = Date()
        let dbMsg = ConversationMessage(
            id: uuid,
            sessionId: UUID(),
            role: .assistant,
            content: "Pong",
            timestamp: date
        )
        
        let msg = dbMsg.toMessage()
        XCTAssertEqual(msg.id, uuid)
        XCTAssertEqual(msg.role, Message.MessageRole.assistant)
        XCTAssertEqual(msg.content, "Pong")
        XCTAssertEqual(msg.timestamp, date)
    }
}
