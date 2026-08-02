import PKShared
import MonadShared
import PositronicKit
import Foundation
@testable import MonadServerCore
import Testing

@Suite(.serialized) struct WebSocketRPCTests {
    @Test("awaitResponse returns result when handleResponse is called with matching id")
    func awaitResponse_success_correlation() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .seconds(5))
        let clientId = UUID()
        let requestId = "test-req-success"

        async let result: AnyCodable = manager.awaitResponse(requestId: requestId, clientId: clientId)

        try await Task.sleep(for: .milliseconds(50))

        let response = RPCResponse(id: requestId, result: AnyCodable("hello"), error: nil)
        await manager.handleResponse(response: response)

        let value = try await result
        #expect(value.value as? String == "hello")
    }

    @Test("awaitResponse times out when no response arrives")
    func awaitResponse_timesOut() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .milliseconds(100))
        let clientId = UUID()
        let requestId = "test-req-timeout"

        do {
            _ = try await manager.awaitResponse(requestId: requestId, clientId: clientId)
            Issue.record("Expected timeout error")
        } catch RPCError.timeout {
            // expected
        } catch {
            Issue.record("Expected timeout, got \(error)")
        }
    }

    @Test("removeConnection cancels pending requests for that client")
    func removeConnection_cancelsPendingRequests() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .seconds(30))
        let clientId = UUID()
        let requestId = "test-req-disconnect"

        async let result: AnyCodable = manager.awaitResponse(requestId: requestId, clientId: clientId)

        try await Task.sleep(for: .milliseconds(50))

        await manager.removeConnection(clientId: clientId)

        do {
            _ = try await result
            Issue.record("Expected connectionLost error")
        } catch RPCError.connectionLost {
            // expected
        } catch {
            Issue.record("Expected connectionLost, got \(error)")
        }
    }

    @Test("handleResponse with error resumes continuation with RPCError.remoteError")
    func handleResponse_errorResponse() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .seconds(5))
        let clientId = UUID()
        let requestId = "test-req-error"

        async let result: AnyCodable = manager.awaitResponse(requestId: requestId, clientId: clientId)

        try await Task.sleep(for: .milliseconds(50))

        let response = RPCResponse(id: requestId, result: nil, error: "remote failure")
        await manager.handleResponse(response: response)

        do {
            _ = try await result
            Issue.record("Expected remoteError")
        } catch let RPCError.remoteError(msg) {
            #expect(msg == "remote failure")
        } catch {
            Issue.record("Expected remoteError, got \(error)")
        }
    }

    @Test("handleResponse with nil result and nil error resumes with NSNull")
    func handleResponse_nullResult() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .seconds(5))
        let clientId = UUID()
        let requestId = "test-req-null"

        async let result: AnyCodable = manager.awaitResponse(requestId: requestId, clientId: clientId)

        try await Task.sleep(for: .milliseconds(50))

        let response = RPCResponse(id: requestId, result: nil, error: nil)
        await manager.handleResponse(response: response)

        let value = try await result
        #expect(value.value is NSNull)
    }

    @Test("removeConnection only cancels requests for the specified client")
    func removeConnection_onlyCancelsSpecifiedClient() async throws {
        let manager = WebSocketConnectionManager(requestTimeout: .seconds(30))
        let clientA = UUID()
        let clientB = UUID()
        let requestA = "test-req-client-a"
        let requestB = "test-req-client-b"

        async let resultA: AnyCodable = manager.awaitResponse(requestId: requestA, clientId: clientA)
        async let resultB: AnyCodable = manager.awaitResponse(requestId: requestB, clientId: clientB)

        try await Task.sleep(for: .milliseconds(50))

        await manager.removeConnection(clientId: clientA)

        do {
            _ = try await resultA
            Issue.record("Expected connectionLost for client A")
        } catch RPCError.connectionLost {
            // expected
        } catch {
            Issue.record("Expected connectionLost for client A, got \(error)")
        }

        let response = RPCResponse(id: requestB, result: AnyCodable("still here"), error: nil)
        await manager.handleResponse(response: response)

        let valueB = try await resultB
        #expect(valueB.value as? String == "still here")
    }
}
