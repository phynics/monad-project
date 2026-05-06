@testable import MonadServer
import Testing

@Suite struct MonadSystemInstructionsTests {
    @Test("Monad host instructions identify the assistant as Monad")
    func system_identifiesAsMonad() {
        let instructions = MonadSystemInstructions.system()

        #expect(instructions.contains("You are Monad, an intelligent developer assistant."))
        #expect(!instructions.contains("You are PositronicKit, an intelligent developer assistant."))
    }
}
