import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Chat API

    /// Send a chat message (non-streaming)
    func chat(
        timelineId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]? = nil,
        clientTools: [ToolReference]? = nil
    ) async throws -> ChatResponse {
        var request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/chat", method: "POST"
        )
        request.httpBody = try await client.encode(
            ChatRequest(
                message: message,
                toolOutputs: toolOutputs,
                clientId: client.configuration.clientId,
                clientTools: clientTools
            )
        )
        return try await client.perform(request)
    }

    /// Cancel an ongoing chat generation
    func cancelChat(timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/chat/cancel", method: "POST"
        )
        _ = try await client.performRaw(request)
    }

    /// Send a chat message with streaming response
    func execute(
        timelineId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]? = nil,
        clientTools: [ToolReference]? = nil
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        client.configuration.logger.debug("execute called for timeline \(timelineId)")
        var request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/chat/stream", method: "POST"
        )
        let clientId = client.configuration.clientId
        request.httpBody = try await client.encode(
            ChatRequest(message: message, toolOutputs: toolOutputs, clientId: clientId, clientTools: clientTools)
        )

        client.configuration.logger.debug(
            "Sending request to \(request.url?.absoluteString ?? "unknown")"
        )
        let (bytes, response) = try await client.fetchStreamBytes(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            client.configuration.logger.error("Invalid response type")
            throw MonadClientError.unknown("Invalid response")
        }

        client.configuration.logger.debug("Response status: \(httpResponse.statusCode)")
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
                client.configuration.logger.error("Failed to read error body: \(error)")
            }

            switch httpResponse.statusCode {
            case 401:
                client.configuration.logger.error("HTTP 401 Unauthorized: \(message ?? "")")
                throw MonadClientError.unauthorized
            case 404:
                client.configuration.logger.error("HTTP 404 Not Found")
                throw MonadClientError.notFound
            default:
                client.configuration.logger.error("HTTP \(httpResponse.statusCode): \(message ?? "")")
                throw MonadClientError.httpError(
                    statusCode: httpResponse.statusCode, message: message
                )
            }
        }

        client.configuration.logger.debug("Starting SSE reader")
        return client.sseReader.events(from: bytes, logger: client.configuration.logger)
    }
}
