import Testing
import Foundation
import Logging
@testable import MonadClient
import MonadCore
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
        
        // Send synthetic HTTP response
        if let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) {
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

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

@Suite(.serialized) final class SSEStreamReaderTests {
    
    var session: URLSession!
    var logger: Logger!
    
    init() {
        // super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        logger = Logger(label: "test.sse")
    }
    
    deinit {
        MockURLProtocol.mockEvents = []
        session = nil
        // super.tearDown()
    }
    
    @Test
    func testSSEStreamReader_SingleMessage() async throws {
        MockURLProtocol.mockEvents = [
            (0, "data: {\"delta\":{\"event\":{\"generation\":{\"text\":\"Hello\"}}}}\n\n"),
            (0, "data: {\"completion\":{\"event\":\"streamCompleted\"}}\n\n"),
            (0, nil)
        ]
        
        let url = URL(string: "https://test.local")!
        let (bytes, _) = try await session.bytes(from: url)
        
        let reader = SSEStreamReader()
        let events = reader.events(from: bytes, logger: logger)
        
        var receivedEvents: [ChatEvent] = []
        for try await event in events {
            receivedEvents.append(event)
        }
        
        #expect(receivedEvents.count == 1)
        #expect(receivedEvents.first?.textContent == "Hello")
    }
    
    @Test
    func testSSEStreamReader_MultipleChunks() async throws {
        MockURLProtocol.mockEvents = [
            (0, "data: {\"delta\":{\"event\":{\"generation\":{\"text\":\"Hel\"}}}}\n"),
            (0.01, "\n"),
            (0.01, "data: {\"delta\":{\"event\":{\"generation\":{\"text\":\"lo\"}}}}\n\n"),
            (0, "data: {\"completion\":{\"event\":\"streamCompleted\"}}\n\n"),
            (0, nil)
        ]
        
        let url = URL(string: "https://test.local")!
        let (bytes, _) = try await session.bytes(from: url)
        
        let reader = SSEStreamReader()
        let events = reader.events(from: bytes, logger: logger)
        
        var contents: [String] = []
        for try await event in events {
            if let c = event.textContent { contents.append(c) }
        }
        
        #expect(contents == ["Hel", "lo"])
    }
}
