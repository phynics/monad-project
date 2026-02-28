import XCTest
import Logging
@testable import MonadClient
import MonadShared

struct ProtocolWrapper: @unchecked Sendable {
    let obj: URLProtocol
    let client: URLProtocolClient
}

class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockEvents: [(delay: TimeInterval, data: String?)] = []
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        let events = MockURLProtocol.mockEvents
        guard let client = self.client else { return }
        let wrapper = ProtocolWrapper(obj: self, client: client)
        
        Task {
            for event in events {
                if event.delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(event.delay * 1_000_000_000))
                }
                if let dataString = event.data {
                    if let data = dataString.data(using: .utf8) {
                        wrapper.client.urlProtocol(wrapper.obj, didLoad: data)
                    }
                } else {
                    wrapper.client.urlProtocolDidFinishLoading(wrapper.obj)
                }
            }
        }
    }
    
    override func stopLoading() {}
}

final class SSEStreamReaderTests: XCTestCase {
    
    var session: URLSession!
    var logger: Logger!
    
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        logger = Logger(label: "test.sse")
    }
    
    override func tearDown() {
        MockURLProtocol.mockEvents = []
        session = nil
        super.tearDown()
    }
    
    func testSSEStreamReader_SingleMessage() async throws {
        let expectation = XCTestExpectation(description: "Stream completes")
        
        MockURLProtocol.mockEvents = [
            (0, "data: {\"type\":\"delta\",\"content\":\"Hello\"}\n\n"),
            (0, "data: [DONE]\n\n"),
            (0, nil)
        ]
        
        let url = URL(string: "https://test.local")!
        let (bytes, _) = try await session.bytes(from: url)
        
        let reader = SSEStreamReader()
        let events = reader.events(from: bytes, logger: logger)
        
        var receivedDeltas: [ChatDelta] = []
        for try await delta in events {
            receivedDeltas.append(delta)
        }
        
        XCTAssertEqual(receivedDeltas.count, 1)
        XCTAssertEqual(receivedDeltas.first?.content, "Hello")
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testSSEStreamReader_MultipleChunks() async throws {
        let expectation = XCTestExpectation(description: "Stream completes")
        
        MockURLProtocol.mockEvents = [
            (0, "data: {\"type\":\"delta\",\"content\":\"Hel\"}\n"),
            (0.01, "\n"),
            (0.01, "data: {\"type\":\"delta\",\"content\":\"lo\"}\n\n"),
            (0, "data: [DONE]\n\n"),
            (0, nil)
        ]
        
        let url = URL(string: "https://test.local")!
        let (bytes, _) = try await session.bytes(from: url)
        
        let reader = SSEStreamReader()
        let events = reader.events(from: bytes, logger: logger)
        
        var contents: [String] = []
        for try await delta in events {
            if let c = delta.content { contents.append(c) }
        }
        
        XCTAssertEqual(contents, ["Hel", "lo"])
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testSSEStreamReader_OpenAILegacyFormat() async throws {
        let expectation = XCTestExpectation(description: "Stream completes")
        
        let openaiJSON = """
        data: {"choices": [{"delta": {"content": "Legacy format", "tool_calls": [{"index": 0, "id": "call_1", "function": {"name": "test_tool", "arguments": "{}"}}]}}]}
        

        """
        
        MockURLProtocol.mockEvents = [
            (0, openaiJSON),
            (0, "data: [DONE]\n\n"),
            (0, nil)
        ]
        
        let url = URL(string: "https://test.local")!
        let (bytes, _) = try await session.bytes(from: url)
        
        let reader = SSEStreamReader()
        let events = reader.events(from: bytes, logger: logger)
        
        var receivedDeltas: [ChatDelta] = []
        for try await delta in events {
            receivedDeltas.append(delta)
        }
        
        XCTAssertEqual(receivedDeltas.count, 1)
        XCTAssertEqual(receivedDeltas[0].content, "Legacy format")
        XCTAssertNotNil(receivedDeltas[0].toolCalls)
        XCTAssertEqual(receivedDeltas[0].toolCalls?.first?.name, "test_tool")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
