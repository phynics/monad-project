import MonadShared
import Hummingbird
import Logging
import Foundation
import MonadCore
import NIOCore

public struct LogMiddleware<Context: RequestContext>: MiddlewareProtocol {
    private static var maxBodyBytes: Int { 64 * 1024 } // 64 KB

    public init() {}

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let start = DispatchTime.now()
        let methodColor = self.color(for: request.method)
        let methodStr = ANSIColors.colorize(request.method.rawValue, color: methodColor)
        let pathStr = ANSIColors.colorize(request.uri.path, color: ANSIColors.brightWhite)

        // Build request log (describe body from headers — we don't consume the body stream)
        let requestBodyInfo = describeRequestBody(request)

        var lines: [String] = []
        lines.append(ANSIColors.colorize("┌─── Request ───────────────────────────────────────", color: ANSIColors.dim))
        lines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(methodStr) \(pathStr)")

        let headerEntries = formatRequestHeaders(request)
        if !headerEntries.isEmpty {
            let headerLabel = ANSIColors.colorize("Headers:", color: ANSIColors.brightBlack)
            lines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(headerLabel) \(headerEntries)")
        }

        if let info = requestBodyInfo {
            let bodyLabel = ANSIColors.colorize("Body:", color: ANSIColors.brightBlack)
            lines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(bodyLabel) \(info)")
        }
        lines.append(ANSIColors.colorize("└───────────────────────────────────────────────────", color: ANSIColors.dim))
        context.logger.info("\n\(lines.joined(separator: "\n"))")

        do {
            let response = try await next(request, context)
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

            let statusColor = self.color(for: response.status.code)
            let statusStr = ANSIColors.colorize("\(response.status.code) \(response.status.reasonPhrase)", color: statusColor)
            let durationStr = ANSIColors.colorize(String(format: "%.3fs", duration), color: ANSIColors.dim)

            // Check if streaming response (SSE) — skip body capture for streams
            let contentType = response.headers[.contentType]
            let isStreaming = contentType?.contains("text/event-stream") == true

            if isStreaming {
                var respLines: [String] = []
                respLines.append(ANSIColors.colorize("┌─── Response ──────────────────────────────────────", color: ANSIColors.dim))
                respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(statusStr)  \(durationStr)")
                if let ct = contentType {
                    let ctLabel = ANSIColors.colorize("Content-Type:", color: ANSIColors.brightBlack)
                    respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(ctLabel) \(ct)")
                }
                let note = ANSIColors.colorize("(SSE stream — body not captured)", color: ANSIColors.dim)
                respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(note)")
                respLines.append(ANSIColors.colorize("└───────────────────────────────────────────────────", color: ANSIColors.dim))
                context.logger.info("\n\(respLines.joined(separator: "\n"))")
                return response
            }

            // Use ResponseBody.map() to intercept the response bytes as they're written.
            // This lets us capture the body for logging while still passing it through to the client.
            let isJSON = contentType?.contains("json") == true
            let logger = context.logger
            let responseStatus = response.status
            let responseHeaders = response.headers

            let mappedBody = response.body.map { (buffer: ByteBuffer) -> ByteBuffer in
                // Log the response body when the buffer is written
                let byteCount = buffer.readableBytes

                var respLines: [String] = []
                respLines.append(ANSIColors.colorize("┌─── Response ──────────────────────────────────────", color: ANSIColors.dim))
                respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(statusStr)  \(durationStr)")
                if let ct = contentType {
                    let ctLabel = ANSIColors.colorize("Content-Type:", color: ANSIColors.brightBlack)
                    respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(ctLabel) \(ct)")
                }

                if byteCount == 0 {
                    let empty = ANSIColors.colorize("(empty)", color: ANSIColors.dim)
                    respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(empty)")
                } else if let str = buffer.getString(at: buffer.readerIndex, length: min(byteCount, Self.maxBodyBytes)) {
                    let bodyLabel = ANSIColors.colorize("Body:", color: ANSIColors.brightBlack)
                    let displayStr: String
                    if isJSON {
                        displayStr = Self.prettifyJSON(str)
                    } else {
                        displayStr = str
                    }
                    let truncated = Self.truncateIfNeeded(displayStr, maxLines: 60)
                    let bodyLines = truncated.components(separatedBy: "\n")
                    respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(bodyLabel)")
                    for bodyLine in bodyLines {
                        respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim))   \(bodyLine)")
                    }
                    if byteCount > Self.maxBodyBytes {
                        respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim))   \(ANSIColors.colorize("… (body truncated at \(Self.formatBytes(Self.maxBodyBytes)))", color: ANSIColors.dim))")
                    }
                } else {
                    let info = ANSIColors.colorize("(binary \(Self.formatBytes(byteCount)))", color: ANSIColors.dim)
                    respLines.append("\(ANSIColors.colorize("│", color: ANSIColors.dim)) \(info)")
                }

                respLines.append(ANSIColors.colorize("└───────────────────────────────────────────────────", color: ANSIColors.dim))
                logger.info("\n\(respLines.joined(separator: "\n"))")

                return buffer
            }

            return Response(
                status: responseStatus,
                headers: responseHeaders,
                body: mappedBody
            )
        } catch {
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            let durationStr = ANSIColors.colorize(String(format: "%.3fs", duration), color: ANSIColors.dim)
            let errorStr = ANSIColors.colorize("ERROR", color: ANSIColors.red)

            var errLines: [String] = []
            errLines.append(ANSIColors.colorize("┌─── Response (Error) ──────────────────────────────", color: ANSIColors.red))
            errLines.append("\(ANSIColors.colorize("│", color: ANSIColors.red)) \(errorStr)  \(durationStr)")
            errLines.append("\(ANSIColors.colorize("│", color: ANSIColors.red)) \(error)")
            errLines.append(ANSIColors.colorize("└───────────────────────────────────────────────────", color: ANSIColors.red))
            context.logger.error("\n\(errLines.joined(separator: "\n"))")
            throw error
        }
    }

    // MARK: - Body Description

    /// Describe the request body from headers only (we don't consume the body stream)
    private func describeRequestBody(_ request: Request) -> String? {
        let contentType = request.headers[.contentType]
        let contentLength = request.headers[.contentLength]

        guard let cl = contentLength, let size = Int(cl), size > 0 else {
            return nil
        }

        let typeInfo = contentType ?? "unknown type"
        return ANSIColors.colorize("(\(Self.formatBytes(size)), \(typeInfo))", color: ANSIColors.dim)
    }

    // MARK: - Formatting Helpers

    private func formatRequestHeaders(_ request: Request) -> String {
        var parts: [String] = []
        if let ct = request.headers[.contentType] {
            parts.append("Content-Type: \(ct)")
        }
        if let cl = request.headers[.contentLength] {
            parts.append("Content-Length: \(cl)")
        }
        if let accept = request.headers[.accept] {
            parts.append("Accept: \(accept)")
        }
        return parts.joined(separator: ", ")
    }

    private static func prettifyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return result
    }

    private static func truncateIfNeeded(_ text: String, maxLines: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count <= maxLines {
            return text
        }
        let truncated = lines.prefix(maxLines).joined(separator: "\n")
        let remaining = lines.count - maxLines
        return truncated + "\n" + ANSIColors.colorize("… (\(remaining) more lines truncated)", color: ANSIColors.dim)
    }

    private static func formatBytes(_ count: Int) -> String {
        if count < 1024 {
            return "\(count) B"
        } else if count < 1024 * 1024 {
            return String(format: "%.1f KB", Double(count) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(count) / (1024.0 * 1024.0))
        }
    }

    // MARK: - Color Helpers

    private func color(for method: HTTPRequest.Method) -> String {
        switch method {
        case .get: return ANSIColors.green
        case .post: return ANSIColors.brightBlue
        case .put, .patch: return ANSIColors.yellow
        case .delete: return ANSIColors.red
        default: return ANSIColors.dim
        }
    }

    private func color(for statusCode: Int) -> String {
        switch statusCode {
        case 200...299: return ANSIColors.green
        case 300...399: return ANSIColors.cyan
        case 400...499: return ANSIColors.yellow
        case 500...599: return ANSIColors.red
        default: return ANSIColors.dim
        }
    }
}
