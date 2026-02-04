import Foundation

struct LocalConfig: Codable {
    var serverURL: String?
    var apiKey: String?
}

struct LocalConfigManager {
    static let shared = LocalConfigManager()

    private var storageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".monad")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("config.json")
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
}
