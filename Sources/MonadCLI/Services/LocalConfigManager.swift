import Foundation

struct LocalConfig: Codable {
    var serverURL: String?
    var apiKey: String?
    var lastSessionId: String?
}

struct LocalConfigManager {
    static let shared = LocalConfigManager()

    private var storageURL: URL {
        let fileManager = FileManager.default
        let appName = "Monad"
        let filename = "config.json"

        #if os(macOS)
            // ~/Library/Application Support/Monad/config.json
            if let appSupport = fileManager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first {
                let dir = appSupport.appendingPathComponent(appName)
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
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
                    ".config")
            }

            let dir = configHome.appendingPathComponent(appName.lowercased())
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(filename)
        #endif

        // Fallback to old path if OS mapping fails or other OS
        let dir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".monad")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    func getConfig() -> LocalConfig {
        guard let data = try? Data(contentsOf: storageURL),
            let config = try? JSONDecoder().decode(LocalConfig.self, from: data)
        else {
            return LocalConfig()
        }
        return config
    }

    func saveConfig(_ config: LocalConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: storageURL)
        } catch {
            // Silently fail or log if we had a logger here
            print("Warning: Failed to save local config: \(error.localizedDescription)")
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
}
