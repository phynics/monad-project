import Foundation
import DiscordBM
import Logging
import GRPC
import NIOCore
import MonadCore

public actor DiscordBridgeEngine {
    private let config: DiscordConfig
    private let gatewayManager: any GatewayManager
    private let discordClient: any DiscordClient
    private let chatClient: MonadChatServiceAsyncClient
    private let channel: GRPCChannel
    private let logger = Logger(label: "com.monad.discord-bridge")
    
    public init(config: DiscordConfig) async throws {
        self.config = config
        
        let botManager = await BotGatewayManager(
            token: config.token,
            presence: .init(
                activities: [.init(name: "Monad Assistant", type: .game)],
                status: .online,
                afk: false
            ),
            intents: [.guildMessages, .directMessages, .messageContent]
        )
        self.gatewayManager = botManager
        self.discordClient = botManager.client
        
        // Setup gRPC
        let group = NIOSingletons.posixEventLoopGroup
        self.channel = try GRPCChannelPool.with(
            target: .host(config.serverHost, port: config.serverPort),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        self.chatClient = MonadChatServiceAsyncClient(channel: channel)
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
            Task {
                await handleMessage(message)
            }
        default:
            break
        }
    }
    
    private func handleMessage(_ message: Gateway.MessageCreate) async {
        // 1. Authorization: Only respond to the hardcoded authorized user
        guard message.author?.id == UserSnowflake(config.authorizedUserId) else {
            return
        }
        
        // 2. Only respond to DMs
        guard message.guild_id == nil else {
            return
        }
        
        logger.info("Received authorized DM: \(message.content)")
        
        do {
            // 3. Initial "Thinking..." response
            let initialResponse = try await discordClient.createMessage(
                channelId: message.channel_id,
                payload: .init(content: "*Thinking...*")
            ).decode()
            
            // 4. Start gRPC stream
            var request = MonadChatRequest()
            request.userQuery = message.content
            request.sessionID = "discord-\(config.authorizedUserId)"
            
            let call = chatClient.makeChatStreamCall(request)
            
            var fullContent = ""
            var lastUpdate = Date()
            
            for try await response in call.responseStream {
                if case .contentDelta(let delta) = response.payload {
                    fullContent += delta
                    
                    // Throttle updates to avoid Discord rate limits (approx every 1.5s)
                    if Date().timeIntervalSince(lastUpdate) > 1.5 {
                        _ = try? await discordClient.updateMessage(
                            channelId: message.channel_id,
                            messageId: initialResponse.id,
                            payload: .init(content: fullContent + " ▌")
                        )
                        lastUpdate = Date()
                    }
                }
            }
            
            // 5. Final update
            _ = try await discordClient.updateMessage(
                channelId: message.channel_id,
                messageId: initialResponse.id,
                payload: .init(content: fullContent)
            )
            
        } catch {
            logger.error("Error handling message: \(error)")
            _ = try? await discordClient.createMessage(
                channelId: message.channel_id,
                payload: .init(content: "❌ Error: \(error.localizedDescription)")
            )
        }
    }
    
    deinit {
        _ = channel.close()
    }
}
