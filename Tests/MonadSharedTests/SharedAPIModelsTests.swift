import XCTest
@testable import MonadShared
@testable import MonadCore
import Foundation

final class SharedAPIModelsTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func assertCodable<T: Codable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(value)
        _ = try decoder.decode(T.self, from: data)
    }
    
    // MARK: - SystemStatus Tests
    
    func testComponentStatusCodable() throws {
        let comp = ComponentStatus(status: .ok, details: ["db": "ok"])
        try assertCodable(comp)
    }
    
    // MARK: - ChatAPI Tests
    
    func testChatAPIModels() throws {
        let req = ChatRequest(message: "Ping", toolOutputs: nil, clientId: UUID())
        // ChatRequest only conforms to Codable, skip Equatable assertion for now
        let data = try JSONEncoder().encode(req)
        XCTAssertGreaterThan(data.count, 0)
        
        let event = ChatEvent.generation("Pong")
        let eData = try JSONEncoder().encode(event)
        XCTAssertGreaterThan(eData.count, 0)
    }
    
    // MARK: - WorkspaceAPI Tests
    
    func testWorkspaceAPIModels() throws {
        let attachReq = AttachWorkspaceRequest(workspaceId: UUID(), isPrimary: true)
        // AttachWorkspaceRequest only conforms to Codable
        let data = try JSONEncoder().encode(attachReq)
        XCTAssertGreaterThan(data.count, 0)
    }
    
    // MARK: - ToolAPI Tests
    
    func testToolInfoCodable() throws {
        let info = ToolInfo(id: "tool-1", name: "test_tool", description: "Does tests")
        // ToolInfo only conforms to Codable and Identifiable, not Equatable
        let data = try JSONEncoder().encode(info)
        XCTAssertGreaterThan(data.count, 0)
    }
    
    // MARK: - ClientModels Tests
    
    func testClientIdentityCodable() throws {
        let client = ClientIdentity(hostname: "macbook", displayName: "Atakan's Mac", platform: "macos")
        let data = try JSONEncoder().encode(client)
        XCTAssertGreaterThan(data.count, 0)
        
        XCTAssertEqual(client.shellWorkspaceURI.host, "macbook")
    }
}
