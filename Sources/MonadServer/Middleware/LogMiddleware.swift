import Foundation
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore

/// Shared formatting context for log line construction
private struct LogFormatContext {
    let dimPipe: String
    let dimFooter: String
    let respHeader: String

    static let shared = LogFormatContext(
        dimPipe: ANSIColors.colorize("│", color: ANSIColors.dim),
        dimFooter: "└───────────────────────────────────────────────────",
        respHeader: "┌─── Response ──────────────────────────────────────"
    )
}

public struct LogMiddleware<Context: RequestContext>: MiddlewareProtocol {
    private static var maxBodyBytes: Int {
        64 * 1024
    } // 64 KB

    /// Pre-computed response metadata for logging
    private struct ResponseLogInfo: @unchecked Sendable {
        let statusStr: String
        let durationStr: String
        let contentType: String?
        let isJSON: Bool

        var isStreaming: Bool {
            contentType?.contains("text/event-stream") == true
        }
    }

    public init() {}

    public func handle(
        _ request: Request, context: Context, next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let start = DispatchTime.now()
        let fmt = LogFormatContext.shared

        logRequest(request, context: context, fmt: fmt)

        do {
            let response = try await next(request, context)
            let info = ResponseLogInfo(
                statusStr: formatStatus(response.status),
                durationStr: formatDuration(since: start),
                contentType: response.headers[.contentType],
                isJSON: response.headers[.contentType]?.contains("json") == true
            )

            if info.isStreaming {
                logStreamingResponse(context: context, info: info, fmt: fmt)
                return response
            }

            return buildMappedResponse(response: response, context: context, info: info, fmt: fmt)
        } catch {
            let durationStr = formatDuration(since: start)
            logErrorResponse(error: error, context: context, durationStr: durationStr, fmt: fmt)
            throw error
        }
    }

    // MARK: - Request Logging

    private func logRequest(_ request: Request, context: Context, fmt: LogFormatContext) {
        let methodColor = color(for: request.method)
        let methodStr = ANSIColors.colorize(request.method.rawValue, color: methodColor)
        let pathStr = ANSIColors.colorize(request.uri.path, color: ANSIColors.brightWhite)
        let requestBodyInfo = describeRequestBody(request)

        var lines: [String] = []
        let reqHeader = "┌─── Request ───────────────────────────────────────"
        lines.append(ANSIColors.colorize(reqHeader, color: ANSIColors.dim))
        lines.append("\(fmt.dimPipe) \(methodStr) \(pathStr)")

        let headerEntries = formatRequestHeaders(request)
        if !headerEntries.isEmpty {
            let headerLabel = ANSIColors.colorize("Headers:", color: ANSIColors.brightBlack)
            lines.append("\(fmt.dimPipe) \(headerLabel) \(headerEntries)")
        }

        if let bodyInfo = requestBodyInfo {
            let bodyLabel = ANSIColors.colorize("Body:", color: ANSIColors.brightBlack)
            lines.append("\(fmt.dimPipe) \(bodyLabel) \(bodyInfo)")
        }
        lines.append(ANSIColors.colorize(fmt.dimFooter, color: ANSIColors.dim))
        context.logger.info("\n\(lines.joined(separator: "\n"))")
    }

    // MARK: - Response Logging

    private func logStreamingResponse(context: Context, info: ResponseLogInfo, fmt: LogFormatContext) {
        var respLines: [String] = []
        respLines.append(ANSIColors.colorize(fmt.respHeader, color: ANSIColors.dim))
        respLines.append("\(fmt.dimPipe) \(info.statusStr)  \(info.durationStr)")
        if let contentTypeVal = info.contentType {
            let ctLabel = ANSIColors.colorize("Content-Type:", color: ANSIColors.brightBlack)
            respLines.append("\(fmt.dimPipe) \(ctLabel) \(contentTypeVal)")
        }
        let note = ANSIColors.colorize("(SSE stream — body not captured)", color: ANSIColors.dim)
        respLines.append("\(fmt.dimPipe) \(note)")
        respLines.append(ANSIColors.colorize(fmt.dimFooter, color: ANSIColors.dim))
        context.logger.info("\n\(respLines.joined(separator: "\n"))")
    }

    private func buildMappedResponse(
        response: Response,
        context: Context,
        info: ResponseLogInfo,
        fmt: LogFormatContext
    ) -> Response {
        let logger = context.logger

        let mappedBody = response.body.map { (buffer: ByteBuffer) -> ByteBuffer in
            let respLines = Self.buildBodyLogLines(buffer: buffer, info: info, fmt: fmt)
            logger.info("\n\(respLines.joined(separator: "\n"))")
            return buffer
        }

        return Response(status: response.status, headers: response.headers, body: mappedBody)
    }

    private static func buildBodyLogLines(
        buffer: ByteBuffer,
        info: ResponseLogInfo,
        fmt: LogFormatContext
    ) -> [String] {
        let byteCount = buffer.readableBytes
        var respLines: [String] = []
        respLines.append(ANSIColors.colorize(fmt.respHeader, color: ANSIColors.dim))
        respLines.append("\(fmt.dimPipe) \(info.statusStr)  \(info.durationStr)")
        if let contentTypeVal = info.contentType {
            let ctLabel = ANSIColors.colorize("Content-Type:", color: ANSIColors.brightBlack)
            respLines.append("\(fmt.dimPipe) \(ctLabel) \(contentTypeVal)")
        }

        if byteCount == 0 {
            let empty = ANSIColors.colorize("(empty)", color: ANSIColors.dim)
            respLines.append("\(fmt.dimPipe) \(empty)")
        } else if let str = buffer.getString(
            at: buffer.readerIndex, length: min(byteCount, maxBodyBytes)
        ) {
            let bodyLabel = ANSIColors.colorize("Body:", color: ANSIColors.brightBlack)
            let displayStr = info.isJSON ? prettifyJSON(str) : str
            let truncated = truncateIfNeeded(displayStr, maxLines: 60)
            let bodyLines = truncated.components(separatedBy: "\n")
            respLines.append("\(fmt.dimPipe) \(bodyLabel)")
            for bodyLine in bodyLines {
                respLines.append("\(fmt.dimPipe)   \(bodyLine)")
            }
            if byteCount > maxBodyBytes {
                let truncMsg = ANSIColors.colorize(
                    "... (body truncated at \(formatBytes(maxBodyBytes)))",
                    color: ANSIColors.dim
                )
                let pipe = ANSIColors.colorize("│", color: ANSIColors.dim)
                respLines.append("\(pipe)   \(truncMsg)")
            }
        } else {
            let binInfo = "(binary \(formatBytes(byteCount)))"
            let binInfoStr = ANSIColors.colorize(binInfo, color: ANSIColors.dim)
            respLines.append("\(fmt.dimPipe) \(binInfoStr)")
        }

        respLines.append(ANSIColors.colorize(fmt.dimFooter, color: ANSIColors.dim))
        return respLines
    }

    private func logErrorResponse(error: Error, context: Context, durationStr: String, fmt: LogFormatContext) {
        let errorStr = ANSIColors.colorize("ERROR", color: ANSIColors.red)
        let redPipe = ANSIColors.colorize("│", color: ANSIColors.red)
        var errLines: [String] = []
        let errHeader = "┌─── Response (Error) ──────────────────────────────"
        errLines.append(ANSIColors.colorize(errHeader, color: ANSIColors.red))
        errLines.append("\(redPipe) \(errorStr)  \(durationStr)")
        errLines.append("\(redPipe) \(error)")
        errLines.append(ANSIColors.colorize(fmt.dimFooter, color: ANSIColors.red))
        context.logger.error("\n\(errLines.joined(separator: "\n"))")
    }

    // MARK: - Timing

    private func formatDuration(since start: DispatchTime) -> String {
        let end = DispatchTime.now()
        let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        return ANSIColors.colorize(String(format: "%.3fs", duration), color: ANSIColors.dim)
    }

    private func formatStatus(_ status: HTTPResponse.Status) -> String {
        let statusColor = color(for: status.code)
        let statusText = "\(status.code) \(status.reasonPhrase)"
        return ANSIColors.colorize(statusText, color: statusColor)
    }

    // MARK: - Body Description

    /// Describe the request body from headers only (we don't consume the body stream)
    private func describeRequestBody(_ request: Request) -> String? {
        let contentType = request.headers[.contentType]
        let contentLength = request.headers[.contentLength]

        guard let contentLengthVal = contentLength, let size = Int(contentLengthVal), size > 0 else {
            return nil
        }

        let typeInfo = contentType ?? "unknown type"
        return ANSIColors.colorize("(\(Self.formatBytes(size)), \(typeInfo))", color: ANSIColors.dim)
    }

    // MARK: - Formatting Helpers

    private func formatRequestHeaders(_ request: Request) -> String {
        var parts: [String] = []
        if let contentTypeVal = request.headers[.contentType] {
            parts.append("Content-Type: \(contentTypeVal)")
        }
        if let contentLengthVal = request.headers[.contentLength] {
            parts.append("Content-Length: \(contentLengthVal)")
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
        case 200 ... 299: return ANSIColors.green
        case 300 ... 399: return ANSIColors.cyan
        case 400 ... 499: return ANSIColors.yellow
        case 500 ... 599: return ANSIColors.red
        default: return ANSIColors.dim
        }
    }
}
