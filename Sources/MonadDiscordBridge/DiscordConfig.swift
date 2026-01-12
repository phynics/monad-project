import Foundation

struct DiscordConfig: Codable, Sendable {
    let token: String
    let authorizedUserId: String
    let serverHost: String
    let serverPort: Int
    
    enum CodingKeys: String, CodingKey {
        case token
        case authorizedUserId = "authorized_user_id"
        case serverHost = "server_host"
        case serverPort = "server_port"
    }
    
    static func load() throws -> DiscordConfig {
        // 1. Try to load from file first as base
        let fileConfig = loadFromFile()
        
        // 2. Override with environment variables
        let envToken = ProcessInfo.processInfo.environment["DISCORD_TOKEN"]
        let envUserId = ProcessInfo.processInfo.environment["DISCORD_USER_ID"]
        let envHost = ProcessInfo.processInfo.environment["MONAD_SERVER_HOST"]
        let envPortStr = ProcessInfo.processInfo.environment["MONAD_SERVER_PORT"]
        let envPort = envPortStr.flatMap { Int($0) }
        
        let finalToken = envToken ?? fileConfig?.token
        let finalUserId = envUserId ?? fileConfig?.authorizedUserId
        let finalHost = envHost ?? fileConfig?.serverHost ?? "localhost"
        let finalPort = envPort ?? fileConfig?.serverPort ?? 50051
        
        guard let token = finalToken, !token.isEmpty else {
            throw ConfigError.missingToken
        }
        
        guard let userId = finalUserId, !userId.isEmpty else {
            throw ConfigError.missingUserId
        }
        
        return DiscordConfig(
            token: token,
            authorizedUserId: userId,
            serverHost: finalHost,
            serverPort: finalPort
        )
    }
    
    private static func loadFromFile() -> DiscordConfig? {
        let path = "discord_config.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(DiscordConfig.self, from: data)
    }
    
    enum ConfigError: Error, LocalizedError {
        case missingToken
        case missingUserId
        
        var errorDescription: String? {
            switch self {
            case .missingToken: return "Discord Bot Token is missing. Provide DISCORD_TOKEN env var or token in discord_config.json"
            case .missingUserId: return "Authorized Discord User ID is missing. Provide DISCORD_USER_ID env var or authorized_user_id in discord_config.json"
            }
        }
    }
}
