import Hummingbird
import Logging
import Foundation
import MonadCore

public struct LogMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let start = DispatchTime.now()
        let methodColor = self.color(for: request.method)
        let methodStr = ANSIColors.colorize(request.method.rawValue, color: methodColor)
        let pathStr = ANSIColors.colorize(request.uri.path, color: ANSIColors.brightWhite)

        context.logger.info("Request: \(methodStr) \(pathStr)")

        do {
            let response = try await next(request, context)
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

            let statusColor = self.color(for: response.status.code)
            let statusStr = ANSIColors.colorize("\(response.status.code)", color: statusColor)
            let durationStr = ANSIColors.colorize(String(format: "%.3fs", duration), color: ANSIColors.dim)

            context.logger.info("Response: \(statusStr) (\(durationStr))")
            return response
        } catch {
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            let durationStr = ANSIColors.colorize(String(format: "%.3fs", duration), color: ANSIColors.dim)

            context.logger.error("Error: \(error) (\(durationStr))")
            throw error
        }
    }

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
