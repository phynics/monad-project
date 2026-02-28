import XCTest
@testable import MonadCore
import Foundation

final class ToolCallTests: XCTestCase {
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded)
    }
    
    func testToolCallRecordCodable() throws {
        let record = ToolCallRecord(
            name: "calculate_sum",
            arguments: "{\"a\": 5, \"b\": 10}",
            turn: 1
        )
        try assertCodable(record)
        XCTAssertEqual(record.name, "calculate_sum")
    }
    
    func testToolResultRecordCodable() throws {
        let result = ToolResultRecord(
            toolCallId: "call_abc123",
            name: "calculate_sum",
            output: "{\"result\": 15}",
            turn: 1
        )
        try assertCodable(result)
        
        let errorResult = ToolResultRecord(
            toolCallId: "call_def456",
            name: "fetch_data",
            output: "Error: Network timeout",
            turn: 2
        )
        try assertCodable(errorResult)
    }
}
