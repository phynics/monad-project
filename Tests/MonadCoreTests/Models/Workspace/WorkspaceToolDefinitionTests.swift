import XCTest
@testable import MonadCore
@testable import MonadShared
import Foundation

final class WorkspaceToolDefinitionTests: XCTestCase {
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded)
    }
    
    func testWorkspaceToolDefinitionCodable() throws {
        let def = WorkspaceToolDefinition(
            id: "tool-id-1",
            name: "test_tool",
            description: "A test tool",
            parametersSchema: ["input": AnyCodable("string")],
            usageExample: "test_tool --input abc",
            requiresPermission: true
        )
        try assertCodable(def)
        XCTAssertEqual(def.id, "tool-id-1")
        XCTAssertTrue(def.requiresPermission)
    }
}
