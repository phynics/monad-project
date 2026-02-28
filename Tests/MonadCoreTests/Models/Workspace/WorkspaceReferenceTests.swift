import XCTest
@testable import MonadCore
import Foundation

final class WorkspaceReferenceTests: XCTestCase {
    private func assertCodable<T: Codable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        _ = try decoder.decode(T.self, from: data)
    }
    
    func testWorkspaceReferenceCodable() throws {
        let ref = WorkspaceReference(
            id: UUID(),
            uri: WorkspaceURI(host: "local", path: "/tmp/test"),
            hostType: .server
        )
        try assertCodable(ref)
    }
    
    func testWorkspaceReferenceWithClientHost() throws {
        let ownerId = UUID()
        let ref = WorkspaceReference(
            id: UUID(),
            uri: WorkspaceURI(host: "macbook", path: "/Users/dev"),
            hostType: .client,
            ownerId: ownerId,
            status: .missing
        )
        try assertCodable(ref)
        XCTAssertEqual(ref.ownerId, ownerId)
        XCTAssertEqual(ref.status, .missing)
    }
}
