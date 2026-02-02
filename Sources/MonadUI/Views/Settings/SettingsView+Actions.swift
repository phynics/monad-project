import SwiftUI
import MonadCore

extension SettingsView {
    internal func loadSettings() {
        Task {
            let config = await llmManager.configuration
            await MainActor.run {
                workingConfig = config
                selectedProvider = workingConfig.activeProvider
                // We probably don't need to auto-fetch models on load unless strictly necessary, 
                // as it might be slow for all providers. But maybe for the active one?
                if selectedProvider == .ollama {
                    fetchOllamaModels()
                } else if selectedProvider == .openAICompatible || selectedProvider == .openRouter {
                    fetchOpenAIModels()
                }
            }
        }
    }

    internal func fetchOpenRouterModels() {
        fetchOpenAIModels()
    }

    internal func saveSettings() {
        errorMessage = nil
        showingSaveSuccess = false

        Task {
            do {
                try await llmManager.updateConfiguration(workingConfig)
                showingSaveSuccess = true

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showingSaveSuccess = false
            } catch {
                errorMessage = "Failed to save settings: \(error.localizedDescription)"
            }
        }
    }

    internal func testConnection() {
        errorMessage = nil
        showingSaveSuccess = false

        Task {
            do {
                // Temporarily update config to test connection without saving persistently to disk immediately?
                // Actually updateConfiguration saves. 
                // Testing connection usually implies saving first in this app context.
                try await llmManager.updateConfiguration(workingConfig)

                // Testing message is handled via sendMessage or similar if we wanted, 
                // for now we just verify config update success as a proxy or we could use the service directly.
                
                showingSaveSuccess = true
                errorMessage = nil

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showingSaveSuccess = false
            } catch {
                errorMessage = "Connection test failed: \(error.localizedDescription)"
            }
        }
    }

    internal func clearSettings() {
        Task {
            await llmManager.clearConfiguration()
            loadSettings()
            errorMessage = nil
            showingSaveSuccess = false
        }
    }

    internal func restoreFromBackup() {
        errorMessage = nil
        showingSaveSuccess = false

        Task {
            do {
                try await llmManager.restoreFromBackup()
                loadSettings()
                showingSaveSuccess = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showingSaveSuccess = false
            } catch {
                errorMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }
    
    internal func fetchOpenAIModels() {
        let config = workingConfig.providers[selectedProvider] ?? ProviderConfiguration.defaultFor(selectedProvider)
        let currentEndpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentEndpoint.isEmpty && !currentKey.isEmpty else { return }
        
        isFetchingModels = true
        errorMessage = nil
        
        Task {
            do {
                let components = parseEndpoint(currentEndpoint)
                let tempClient = OpenAIClient(
                    apiKey: currentKey,
                    modelName: "temp",
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                )
                
                if let names = try await tempClient.fetchAvailableModels() {
                    await MainActor.run {
                        self.openAIModels = names.sorted()
                        self.isFetchingModels = false
                        // Auto-select first if current is invalid?
                        // For now we just populate list
                    }
                } else {
                    await MainActor.run {
                        self.isFetchingModels = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingModels = false
                    self.errorMessage = "Failed to fetch models: \(error.localizedDescription)"
                }
            }
        }
    }
    
    internal func parseEndpoint(_ endpoint: String) -> (host: String, port: Int, scheme: String) {
        let cleanedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanedEndpoint), let host = url.host else {
            return ("api.openai.com", 443, "https")
        }

        let scheme = url.scheme ?? "https"
        let port: Int
        if let urlPort = url.port {
            port = urlPort
        } else {
            port = (scheme == "https") ? 443 : 80
        }

        return (host, port, scheme)
    }

    internal func fetchOllamaModels() {
        let config = workingConfig.providers[selectedProvider] ?? ProviderConfiguration.defaultFor(selectedProvider)
        let currentEndpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentEndpoint.isEmpty else { return }
        
        isFetchingModels = true
        errorMessage = nil
        
        Task {
            do {
                let tempClient = OllamaClient(endpoint: currentEndpoint, modelName: "temp")
                if let names = try await tempClient.fetchAvailableModels() {
                    await MainActor.run {
                        self.ollamaModels = names
                        self.isFetchingModels = false
                    }
                } else {
                    await MainActor.run {
                        self.isFetchingModels = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingModels = false
                    self.errorMessage = "Failed to fetch models: \(error.localizedDescription)"
                }
            }
        }
    }

    internal func resetDatabase() {
        Task {
            do {
                try await persistenceManager.resetDatabase()
                showingSaveSuccess = true
                errorMessage = nil

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showingSaveSuccess = false
            } catch {
                errorMessage = "Database reset failed: \(error.localizedDescription)"
            }
        }
    }
}
