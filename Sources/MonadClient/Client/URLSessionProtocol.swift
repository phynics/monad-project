import Foundation

/// A protocol representing the capabilities of `URLSession` needed by `MonadClient`.
/// This enables mocking of the network layer in tests without utilizing private or un-instantiable OS-level types.
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse)
}

// Conform the standard Foundation URLSession to this protocol
extension URLSession: URLSessionProtocol {
    public func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request, delegate: nil)
        return (bytes, response)
    }
}
