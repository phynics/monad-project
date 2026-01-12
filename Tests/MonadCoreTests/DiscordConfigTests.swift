import Foundation
import Testing
@testable import MonadDiscordBridge

@Suite struct DiscordConfigTests {
    
    @Test("Test error when configuration is missing")
    func testMissingConfig() {
        // Clear environment variables for test
        setenv("DISCORD_TOKEN", "", 1)
        setenv("DISCORD_USER_ID", "", 1)
        
        #expect(throws: DiscordConfig.ConfigError.missingToken) {
            _ = try DiscordConfig.load()
        }
    }
}
