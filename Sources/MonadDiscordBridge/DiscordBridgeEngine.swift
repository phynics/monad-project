import Foundation
import DiscordBM
import Logging

public actor DiscordBridgeEngine {
    private let config: DiscordConfig
    private let gatewayManager: any GatewayManager
    private let logger = Logger(label: "com.monad.discord-bridge")
    
    public init(config: DiscordConfig) async {
        self.config = config
        self.gatewayManager = await BotGatewayManager(
            token: config.token,
            presence: .init(
                activities: [.init(name: "Monad Assistant", type: .game)],
                status: .online,
                afk: false
            ),
            intents: [.guildMessages, .directMessages, .messageContent]
        )
    }
    
    public func connect() async {
        logger.info("Connecting to Discord Gateway...")
        await gatewayManager.connect()
        
        Task {
            for await event in await gatewayManager.events {
                handleEvent(event)
            }
        }
    }
    
    private func handleEvent(_ event: Gateway.Event) {
        switch event.data {
        case let .messageCreate(message):
            handleMessage(message)
        default:
            break
        }
    }
    
    private func handleMessage(_ message: Gateway.MessageCreate) {
        // 1. Authorization: Only respond to the hardcoded authorized user
        guard message.author?.id == UserSnowflake(config.authorizedUserId) else {
            return
        }
        
        // 2. Only respond to DMs (or @mentions if we wanted, but spec says DMs)
        // message.guild_id == nil means it's a DM
        guard message.guild_id == nil else {
            return
        }
        
        logger.info("Received authorized DM: \(message.content)")
        
        // TODO: Forward to gRPC in Phase 3
    }
}
