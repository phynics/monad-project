import Foundation
import MonadClient

extension ChatREPL {
    func handleError(_ error: Error) async {
        logger.error("ChatREPL error: \(error)")

        if let clientError = error as? MonadClientError {
            switch clientError {
            case .unauthorized:
                TerminalUI.printError("Unauthorized. Please check your API key or configuration.")
            case .serverNotReachable:
                TerminalUI.printError("Server not reachable. Please ensure the server is running.")
            case .notFound:
                TerminalUI.printError("Resource not found.")
            case let .httpError(statusCode, message):
                TerminalUI.printError("HTTP Error \(statusCode): \(message ?? "Unknown")")
            case let .networkError(err):
                TerminalUI.printError("Network Error: \(err.localizedDescription)")
            case let .decodingError(err):
                TerminalUI.printError("Decoding Error: \(err.localizedDescription)")
            case .invalidURL:
                TerminalUI.printError("Invalid URL.")
            case let .unknown(msg):
                TerminalUI.printError("Error: \(msg)")
            }
        } else {
            TerminalUI.printError("Error: \(error.localizedDescription)")
        }
    }
}
