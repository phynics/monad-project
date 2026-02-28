import XCTest
@testable import MonadCore
import Foundation

final class ToolReferenceTests: XCTestCase {
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded)
    }
    
    func testToolReferenceCodable() throws {
        let ref = ToolReference.known("search-api")
        try assertCodable(ref)
        XCTAssertEqual(ref.displayName, "search-api")
        XCTAssertEqual(ref.toolId, "search-api")
    }
    
    func testToolReferenceWithWorkspace() throws {
        let def = WorkspaceToolDefinition(
            id: "list-files",
            name: "List Files",
            description: "Lists workspace files"
        )
        let ref = ToolReference.custom(def)
        try assertCodable(ref)
        XCTAssertEqual(ref.displayName, "List Files") 
        XCTAssertEqual(ref.toolId, "list-files")
    }
}
