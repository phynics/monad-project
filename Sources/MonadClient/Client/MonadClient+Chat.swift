import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Chat API

    /// Send a chat message (non-streaming)
    public func chat(sessionId: UUID, message: String, toolOutputs: [ToolOutputSubmission]? = nil, clientTools: [ToolReference]? = nil) async throws -> ChatResponse {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat", method: "POST")
        request.httpBody = try encoder.encode(
            ChatRequest(message: message, toolOutputs: toolOutputs, clientId: configuration.clientId, clientTools: clientTools))
        return try await perform(request)
    }

    /// Cancel an ongoing chat generation
    public func cancelChat(sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/cancel", method: "POST")
        _ = try await performRaw(request)
    }

    /// Send a chat message with streaming response
    public func chatStream(sessionId: UUID, message: String, toolOutputs: [ToolOutputSubmission]? = nil, clientTools: [ToolReference]? = nil) async throws -> AsyncThrowingStream<
        ChatEvent, Error
    > {
        configuration.logger.debug("chatStream called for session \(sessionId)")
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/stream", method: "POST")
        request.httpBody = try encoder.encode(
            ChatRequest(message: message, toolOutputs: toolOutputs, clientId: configuration.clientId, clientTools: clientTools))

        configuration.logger.debug(
            "Sending request to \(request.url?.absoluteString ?? "unknown")")
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            configuration.logger.error("Invalid response type")
            throw MonadClientError.unknown("Invalid response")
        }

        configuration.logger.debug("Response status: \(httpResponse.statusCode)")
        if httpResponse.statusCode != 200 {
            // Read error body if possible
            var message: String?
            do {
                var body = ""
                for try await byte in bytes {
                    body.append(Character(UnicodeScalar(byte)))
                }
                message = body
            } catch {
                configuration.logger.error("Failed to read error body: \(error)")
            }

            switch httpResponse.statusCode {
            case 401:
                configuration.logger.error("HTTP 401 Unauthorized: \(message ?? "")")
                throw MonadClientError.unauthorized
            case 404:
                configuration.logger.error("HTTP 404 Not Found")
                throw MonadClientError.notFound
            default:
                configuration.logger.error("HTTP \(httpResponse.statusCode): \(message ?? "")")
                throw MonadClientError.httpError(
                    statusCode: httpResponse.statusCode, message: message)
            }
        }

        configuration.logger.debug("Starting SSE reader")
        return sseReader.events(from: bytes, logger: configuration.logger)
    }
}
