import Testing
@testable import MonadCore
@testable import MonadShared
import Foundation

@Suite final class TimelineTests {
    private func assertCodable<T: Codable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(value)
        _ = try decoder.decode(T.self, from: data)
    }
    
    @Test

    
    func testTimelineCodable() throws {
        let timeline = Timeline(
            title: "Test Session"
        )
        try assertCodable(timeline)
    }
    
    @Test

    
    func testTimelineWithWorkspacesCodable() throws {
        let primaryId = UUID()
        let attachedId = UUID()
        let timeline = Timeline(
            title: "Project Alpha",
            primaryWorkspaceId: primaryId,
            attachedWorkspaceIds: [attachedId]
        )
        
        try assertCodable(timeline)
        #expect(timeline.primaryWorkspaceId == primaryId)
        #expect(timeline.attachedWorkspaces.first == attachedId)
    }
}
