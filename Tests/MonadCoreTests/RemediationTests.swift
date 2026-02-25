import Testing
import Foundation
@testable import MonadCore
import MonadShared

@Suite("Remediation and Validation Tests")
struct RemediationTests {
    
    @Test("ToolError provides remediation hints")
    func testToolErrorRemediation() {
        let missingArg = ToolError.missingArgument("path")
        #expect(missingArg.remediation != nil)
        #expect(missingArg.remediation?.contains("Check the tool definition") == true)
        
        let invalidArg = ToolError.invalidArgument("count", expected: "Int", got: "String")
        #expect(invalidArg.remediation?.contains("Convert the value") == true)
    }
    
    @Test("Configuration validation identifies missing API keys")
    func testConfigurationValidation() {
        var config = Configuration.default
        config.llm.providers[.openAI] = ProviderConfiguration(
            endpoint: "test",
            apiKey: "",
            modelName: "gpt-4",
            utilityModel: "gpt-4",
            fastModel: "gpt-4",
            toolFormat: .openAI
        )
        
        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }
}
