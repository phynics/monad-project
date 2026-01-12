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
    private let channel: GRPCChannel?
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
        
        // Setup gRPC with better defaults
        let group = NIOSingletons.posixEventLoopGroup
        let channel = try GRPCChannelPool.with(
            target: .host(config.serverHost, port: config.serverPort),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        ) {
            // Connection management
            $0.connectionBackoff = ConnectionBackoff(
                initialBackoff: 1.0,
                maximumBackoff: 30.0,
                multiplier: 1.6
            )
        }
        self.channel = channel
        self.chatClient = MonadChatServiceAsyncClient(channel: channel)
    }
    
    /// Test-only initializer
    internal init(
        config: DiscordConfig,
        gatewayManager: any GatewayManager,
        discordClient: any DiscordClient,
        chatClient: MonadChatServiceAsyncClient
    ) {
        self.config = config
        self.gatewayManager = gatewayManager
        self.discordClient = discordClient
        self.chatClient = chatClient
        self.channel = nil
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
        case .ready:
            logger.info("Discord Gateway is Ready.")
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
            // 3. Update status and typing
            await gatewayManager.updatePresence(payload: .init(
                activities: [.init(name: "Thinking...", type: .game)],
                status: .online,
                afk: false
            ))
            
            // 3.1 Initial "Thinking..." response
            let initialResponse = try await discordClient.createMessage(
                channelId: message.channel_id,
                payload: .init(content: "*Thinking...*")
            ).decode()
            
            // 4. Start gRPC stream
            var request = MonadChatRequest()
            request.userQuery = message.content
            request.sessionID = "discord-\(config.authorizedUserId)"
            
            let call = chatClient.makeChatStreamCall(request, callOptions: .init(timeLimit: .timeout(.seconds(60))))
            
            var fullContent = ""
            var lastUpdate = Date()
            var accumulatedEmbeds: [Embed] = []
            
            for try await response in call.responseStream {
                switch response.payload {
                case .contentDelta(let delta):
                    fullContent += delta
                    
                    // Throttle updates to avoid Discord rate limits (approx every 1.5s)
                    if Date().timeIntervalSince(lastUpdate) > 1.5 {
                        _ = try? await discordClient.updateMessage(
                            channelId: message.channel_id,
                            messageId: initialResponse.id,
                            payload: .init(content: fullContent + " ▌", embeds: accumulatedEmbeds)
                        )
                        lastUpdate = Date()
                    }
                case .metadata(let metadata):
                    accumulatedEmbeds.append(DiscordEmbedMapper.mapMetadata(metadata))
                case .toolCall(let toolCall):
                    accumulatedEmbeds.append(DiscordEmbedMapper.mapToolCall(toolCall))
                case .finalMessage(let finalMessage):
                    if let embed = DiscordEmbedMapper.mapFinalMessage(finalMessage) {
                        accumulatedEmbeds.append(embed)
                    }
                default:
                    break
                }
            }
            
            // 5. Final update
            _ = try await discordClient.updateMessage(
                channelId: message.channel_id,
                messageId: initialResponse.id,
                payload: .init(content: fullContent, embeds: accumulatedEmbeds)
            )
            
            // 6. Reset status
            await gatewayManager.updatePresence(payload: .init(
                activities: [.init(name: "Monad Assistant", type: .game)],
                status: .online,
                afk: false
            ))
            
        } catch {
            logger.error("Error handling message: \(error)")
            _ = try? await discordClient.createMessage(
                channelId: message.channel_id,
                payload: .init(content: "❌ Error: \(error.localizedDescription)")
            )
            // Reset status on error
            await gatewayManager.updatePresence(payload: .init(
                activities: [.init(name: "Monad Assistant", type: .game)],
                status: .online,
                afk: false
            ))
        }
    }
    
    deinit {
        _ = channel?.close()
    }
}
