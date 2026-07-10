import Foundation
@testable import MonadCLICore
import Testing

@Suite struct ToolCallingDiagnosticsTests {
    @Test("tool-only stream without assistant output emits a diagnostic")
    func toolOnlyStream_emitsDiagnostic() {
        let state = ToolCallingDiagnostics.State(
            assistantStarted: false,
            sawGenerationContent: false,
            sawGenerationCompleted: false,
            sawToolCallDelta: true,
            sawToolExecutionEvent: false,
            streamedToolCallNames: ["dummy_tool", "ls", "timeline_peek"]
        )

        let diagnostic = ToolCallingDiagnostics.message(for: state)

        #expect(diagnostic != nil)
        #expect(diagnostic?.contains("dummy_tool") == true)
        #expect(diagnostic?.contains("timeline_peek") == true)
    }

    @Test("normal assistant output does not emit a diagnostic")
    func normalOutput_doesNotEmitDiagnostic() {
        let state = ToolCallingDiagnostics.State(
            assistantStarted: true,
            sawGenerationContent: true,
            sawGenerationCompleted: true,
            sawToolCallDelta: false,
            sawToolExecutionEvent: false,
            streamedToolCallNames: []
        )

        #expect(ToolCallingDiagnostics.message(for: state) == nil)
    }
}
