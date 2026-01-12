import Foundation
import Testing
@testable import MonadDiscordBridge

@Suite struct DiscordConfigTests {
    
    @Test("Test environment variable priority")
    func testEnvPriority() throws {
        // 0. Ensure clean env
        unsetenv("DISCORD_TOKEN")
        unsetenv("DISCORD_USER_ID")
        
        // 1. Setup a dummy config file
        let config = ["token": "file-token", "authorized_user_id": "file-user"]
        let data = try JSONEncoder().encode(config)
        let filePath = "discord_config.json"
        try data.write(to: URL(fileURLWithPath: filePath))
        defer { try? FileManager.default.removeItem(atPath: filePath) }
        
        // 2. Set environment variables
        setenv("DISCORD_TOKEN", "env-token", 1)
        setenv("DISCORD_USER_ID", "env-user", 1)
        defer {
            unsetenv("DISCORD_TOKEN")
            unsetenv("DISCORD_USER_ID")
        }
        
        // 3. Load and verify
        let loaded = try DiscordConfig.load()
        #expect(loaded.token == "env-token")
        #expect(loaded.authorizedUserId == "env-user")
    }

    @Test("Test error when configuration is missing")
    func testMissingConfig() {
        // Clear environment variables for test
        unsetenv("DISCORD_TOKEN")
        unsetenv("DISCORD_USER_ID")
        
        #expect(throws: DiscordConfig.ConfigError.missingToken) {
            _ = try DiscordConfig.load()
        }
    }
}