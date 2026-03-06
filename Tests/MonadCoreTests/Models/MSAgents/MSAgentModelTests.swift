import XCTest
@testable import MonadCore
@testable import MonadShared
import Foundation

final class MSAgentModelTests: XCTestCase {
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded)
    }
    
    func testMSAgentCodable() throws {
        // MSAgent initialization
        let agent = MSAgent(
            id: UUID(),
            name: "Worker",
            description: "Does tasks.",
            systemPrompt: "You follow instructions.",
            personaPrompt: "Be professional.",
            guardrailsPrompt: "Don't break things."
        )
        
        try assertCodable(agent)
        
        // Test composedInstructions
        XCTAssertTrue(agent.composedInstructions.contains("You follow instructions."))
        XCTAssertTrue(agent.composedInstructions.contains("## Persona"))
        XCTAssertTrue(agent.composedInstructions.contains("Be professional."))
        XCTAssertTrue(agent.composedInstructions.contains("## Guardrails"))
        XCTAssertTrue(agent.composedInstructions.contains("Don't break things."))
    }
}
