import Foundation
import GRPC
import Metrics
import Logging
import MonadCore

/// A centralized error handler for MonadServer that unifies error mapping,
/// logging, and telemetry recording.
///
/// Adheres to **SOLID** principles by separating error handling logic 
/// from gRPC business handlers (Separation of Concerns).
public final class ServerErrorHandler: Sendable {
    private let logger = Logger(label: "com.monad.server.error-handler")
    
    public init() {}
    
    /// Handles an error by logging it, incrementing metrics, and mapping it to a `GRPCStatus`.
    /// 
    /// This method is the single source of truth for how errors are presented to clients
    /// and recorded in our observability stack.
    ///
    /// - Parameters:
    ///   - error: The source error to handle.
    ///   - context: A string describing the context where the error occurred (e.g., "chat_stream").
    /// - Returns: A mapped `GRPCStatus` ready to be returned to the client.
    public func handle(_ error: Error, context: String) -> GRPCStatus {
        let status = map(error)
        
        // Record telemetry: Increment the error counter with the context and code as dimensions
        Counter(label: "monad_server_errors_total", dimensions: [
            ("context", context),
            ("code", "\(status.code.rawValue)")
        ]).increment()
        
        // Log the error with structured metadata
        logger.error("Error in \(context): \(error.localizedDescription)", metadata: [
            "grpc_code": "\(status.code.rawValue)",
            "error_details": "\(error)"
        ])
        
        return status
    }
    
    /// Maps internal domain errors or external library errors to standard gRPC status codes.
    ///
    /// - Parameter error: The raw error caught by a handler.
    /// - Returns: The most appropriate `GRPCStatus`.
    private func map(_ error: Error) -> GRPCStatus {
        if let status = error as? GRPCStatus {
            return status
        }
        
        // Future: Add more specific domain error mappings here.
        // Adheres to the Open/Closed principle by allowing new mappings
        // without changing the high-level 'handle' logic.
        
        return GRPCStatus(code: .internalError, message: error.localizedDescription)
    }
}