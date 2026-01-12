import Foundation
import MonadCore
import GRPC
import NIOPosix
import NIOCore
import Observation

@MainActor
@Observable
public final class ServiceCoordinator {
    public private(set) var activeLLMService: any LLMServiceProtocol
    public private(set) var activePersistenceService: any PersistenceServiceProtocol
    
    private let localLLMService: LLMService
    private let localPersistenceService: PersistenceService
    
    private var remoteChannel: GRPCChannel?
    
    public init(localLLM: LLMService, localPersistence: PersistenceService) {
        self.localLLMService = localLLM
        self.localPersistenceService = localPersistence
        self.activeLLMService = localLLM
        self.activePersistenceService = localPersistence
    }
    
    public func update(with config: LLMConfiguration) async throws {
        if config.connectionMode == .remote {
            // Setup remote services
            let host = config.monadServer.host
            let port = config.monadServer.port
            
            // Close old channel if needed
            if let oldChannel = remoteChannel {
                _ = oldChannel.close()
            }
            
            let group = NIOSingletons.posixEventLoopGroup
            let channel = try GRPCChannelPool.with(
                target: .host(host, port: port),
                transportSecurity: .plaintext,
                eventLoopGroup: group
            )
            
            self.remoteChannel = channel
            self.activeLLMService = gRPCLLMService(channel: channel)
            self.activePersistenceService = gRPCPersistenceService(channel: channel)
            
            print("Switched to Remote mode: \(host):\(port)")
        } else {
            // Use local services
            self.activeLLMService = localLLMService
            self.activePersistenceService = localPersistenceService
            
            // Close remote channel if it was open
            if let oldChannel = remoteChannel {
                _ = oldChannel.close()
                self.remoteChannel = nil
            }
            
            print("Switched to Local mode")
        }
    }
}
