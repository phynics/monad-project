import XCTest
@testable import MonadCore
import Foundation

final class APIResponseMetadataTests: XCTestCase {
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded)
    }
    
    func testAPIResponseMetadataCodable() throws {
        let metadata = APIResponseMetadata(
            model: "claude-3-opus",
            promptTokens: 100,
            completionTokens: 50,
            totalTokens: 150,
            duration: 2.5,
            tokensPerSecond: 45.2
        )
        try assertCodable(metadata)
    }
    
    func testAPIResponseMetadataWithNilTokens() throws {
        let metadata = APIResponseMetadata(
            model: "gpt-4",
            promptTokens: Optional<Int>.none,
            completionTokens: Optional<Int>.none,
            totalTokens: Optional<Int>.none,
            duration: 1.0,
            tokensPerSecond: 20.0
        )
        try assertCodable(metadata)
    }
    
    func testAPIResponseMetadataPerformanceCalc() {
        let metadata = APIResponseMetadata(model: "test", duration: 1.5, tokensPerSecond: 100)
        XCTAssertEqual(metadata.duration, 1.5)
        XCTAssertEqual(metadata.tokensPerSecond, 100)
    }
}
