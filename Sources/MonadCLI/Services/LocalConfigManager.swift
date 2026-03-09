import Foundation
import Logging
import MonadShared

struct LocalConfig: Codable {
    var serverURL: String?
    var apiKey: String?
    var lastSessionId: String?
    var lastAgentInstanceId: String?
    var clientWorkspaces: [String: String]? // URI -> WorkspaceID
}

struct LocalConfigManager {
    static let shared = LocalConfigManager()
    private let logger = Logger.module(named: "local-config")

    private let customStorageURL: URL?

    init(storageURL: URL? = nil) {
        customStorageURL = storageURL
    }

    private var storageURL: URL {
        if let custom = customStorageURL { return custom }

        let fileManager = FileManager.default
        let appName = "Monad"
        let filename = "config.json"

        #if os(macOS)
            // ~/Library/Application Support/Monad/config.json
            if let appSupport = fileManager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first {
                let dir = appSupport.appendingPathComponent(appName)
                do {
                    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create application support directory: \(error)")
                }
                return dir.appendingPathComponent(filename)
            }
        #elseif os(Linux)
            // XDG_CONFIG_HOME or ~/.config/monad/config.json
            let env = ProcessInfo.processInfo.environment
            let configHome: URL
            if let xdgConfig = env["XDG_CONFIG_HOME"] {
                configHome = URL(fileURLWithPath: xdgConfig)
            } else {
                configHome = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                    ".config"
                )
            }

            let dir = configHome.appendingPathComponent(appName.lowercased())
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create config directory: \(error)")
            }
            return dir.appendingPathComponent(filename)
        #endif

        // Fallback to old path if OS mapping fails or other OS
        let dir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".monad")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create .monad directory: \(error)")
        }
        return dir.appendingPathComponent(filename)
    }

    func getConfig() -> LocalConfig {
        guard let data = try? Data(contentsOf: storageURL) else {
            return LocalConfig()
        }
        do {
            return try JSONDecoder().decode(LocalConfig.self, from: data)
        } catch {
            logger.error("Failed to decode local config: \(error)")
            return LocalConfig()
        }
    }

    func saveConfig(_ config: LocalConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: storageURL)
            logger.debug("Successfully saved local config to \(storageURL.path)")
        } catch {
            logger.error("Failed to save local config to \(storageURL.path): \(error)")
            print(ANSIColors.colorize("Warning: Failed to save local config: \(error.localizedDescription)", color: ANSIColors.yellow))
        }
    }

    func updateServerURL(_ url: String) {
        var config = getConfig()
        config.serverURL = url
        saveConfig(config)
    }

    func updateLastSessionId(_ id: String) {
        var config = getConfig()
        config.lastSessionId = id
        saveConfig(config)
    }

    func updateLastAgentInstanceId(_ id: String?) {
        var config = getConfig()
        config.lastAgentInstanceId = id
        saveConfig(config)
    }

    func updateClientWorkspaces(_ workspaces: [String: String]) {
        var config = getConfig()
        config.clientWorkspaces = workspaces
        saveConfig(config)
    }

    func saveClientWorkspace(uri: String, id: String) {
        var config = getConfig()
        var workspaces = config.clientWorkspaces ?? [:]
        workspaces[uri] = id
        config.clientWorkspaces = workspaces
        saveConfig(config)
    }
}
