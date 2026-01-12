import Foundation
import Logging

struct DiscordBridgeApp {
    static func run() async throws {
        print("Monad Discord Bridge starting...")
        
        // 1. Load Configuration
        let config: DiscordConfig
        do {
            config = try DiscordConfig.load()
        } catch {
            print("Configuration Error: \(error.localizedDescription)")
            exit(1)
        }
        
        print("Configuration loaded for User: \(config.authorizedUserId)")
        
        // 2. Setup Engine
        let engine = await DiscordBridgeEngine(config: config)
        
        // 3. Connect
        await engine.connect()
        
        // 4. Run loop
        print("Bridge is running. Press Ctrl+C to exit.")
        try await Task.sleep(nanoseconds: UInt64.max)
    }
}
