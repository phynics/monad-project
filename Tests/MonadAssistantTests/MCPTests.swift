import XCTest

@testable import MonadAssistant

final class MCPTests: XCTestCase {

    // Mock Transport for testing
    actor MockTransport: MCPTransport {
        nonisolated let messages: AsyncStream<Data>
        private let continuation: AsyncStream<Data>.Continuation

        var sentData: [Data] = []

        init() {
            var cont: AsyncStream<Data>.Continuation!
            self.messages = AsyncStream { c in cont = c }
            self.continuation = cont
        }

        func start() async throws {}
        func close() async {}

        func send(_ data: Data) async throws {
            sentData.append(data)
        }

        func inject(_ string: String) {
            if let data = string.data(using: .utf8) {
                continuation.yield(data)
            }
        }
    }

    func testClientInitialization() async throws {
        let transport = MockTransport()
        let client = MCPClient(transport: transport)
        // Just verify it doesn't crash on init
        _ = client
    }

    func testJSONRPCModels() throws {
        // Test Request Encoding
        let req = JSONRPCRequest(id: 1, method: "test", params: nil)
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"method\":\"test\""))
        XCTAssertTrue(json.contains("\"jsonrpc\":\"2.0\""))

        // Test Response Decoding
        let regex = #"{"jsonrpc":"2.0","id":1,"result":{"foo":"bar"}}"#
        let resData = regex.data(using: .utf8)!
        let res = try JSONDecoder().decode(JSONRPCResponse.self, from: resData)

        XCTAssertEqual(res.id, 1)
        // Extract result... AnyCodable usage
        // This is a basic sanity check
    }
}
