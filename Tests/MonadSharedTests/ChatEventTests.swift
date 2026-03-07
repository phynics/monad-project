import XCTest
@testable import MonadShared
import Foundation

final class ChatEventTests: XCTestCase {
    func testGenerationCancelledEvent() throws {
        // This should fail to compile after the rename or if I use the new name now
        // But for TDD, I should write something that expects 'generationCancelled'
        let event = ChatEvent.generationCancelled()
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChatEvent.self, from: data)
        
        if case let .error(errorEvent) = decoded {
            if case .generationCancelled = errorEvent {
                // Success
            } else {
                XCTFail("Expected .generationCancelled, got \(errorEvent)")
            }
        } else {
            XCTFail("Expected .error, got \(decoded)")
        }
    }
}
