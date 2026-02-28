import XCTest
@testable import MonadCore
import Foundation

final class TimelineTests: XCTestCase {
    private func assertCodable<T: Codable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(value)
        _ = try decoder.decode(T.self, from: data)
    }
    
    func testTimelineCodable() throws {
        let timeline = Timeline(
            title: "Test Session"
        )
        try assertCodable(timeline)
    }
    
    func testTimelineWithWorkspacesCodable() throws {
        let primaryId = UUID()
        let attachedId = UUID()
        let timeline = Timeline(
            title: "Project Alpha",
            primaryWorkspaceId: primaryId,
            attachedWorkspaceIds: [attachedId]
        )
        
        try assertCodable(timeline)
        XCTAssertEqual(timeline.primaryWorkspaceId, primaryId)
        XCTAssertEqual(timeline.attachedWorkspaces.first, attachedId)
    }
}
