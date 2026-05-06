import Foundation

enum ToolCallingDiagnostics {
    struct State: Equatable {
        var assistantStarted: Bool
        var sawGenerationContent: Bool
        var sawGenerationCompleted: Bool
        var sawToolCallDelta: Bool
        var sawToolExecutionEvent: Bool
        var streamedToolCallNames: [String]
    }

    static func message(for state: State) -> String? {
        guard !state.sawGenerationContent, !state.sawGenerationCompleted else {
            return nil
        }

        guard state.sawToolCallDelta || state.sawToolExecutionEvent else {
            return nil
        }

        let tools = state.streamedToolCallNames.isEmpty
            ? "unknown tools"
            : state.streamedToolCallNames.joined(separator: ", ")

        return "Tool-calling diagnostic: the stream ended without assistant text or a completed message, but tool activity was observed for \(tools). Inspect streamed tool-call handling and provider finish reasons."
    }
}
