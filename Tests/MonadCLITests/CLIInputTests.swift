import Testing
@testable import MonadCLICore

@Suite struct CLIInputTests {
    @Test("confirmation parser accepts yes variants")
    func confirmationYesVariants() {
        #expect(CLIInput.isAffirmative("y"))
        #expect(CLIInput.isAffirmative("Y"))
        #expect(CLIInput.isAffirmative(" yes "))
    }

    @Test("confirmation parser rejects non-affirmative values")
    func confirmationRejectsOthers() {
        #expect(!CLIInput.isAffirmative(""))
        #expect(!CLIInput.isAffirmative("n"))
        #expect(!CLIInput.isAffirmative("no"))
        #expect(!CLIInput.isAffirmative("anything else"))
    }
}
