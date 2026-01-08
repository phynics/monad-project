import SwiftUI
import MonadCore

extension SettingsView {
    internal func loadSettings() {
        provider = llmService.configuration.provider
        endpoint = llmService.configuration.endpoint
        modelName = llmService.configuration.modelName
        utilityModel = llmService.configuration.utilityModel
        fastModel = llmService.configuration.fastModel
        apiKey = llmService.configuration.apiKey
        toolFormat = llmService.configuration.toolFormat
        mcpServers = llmService.configuration.mcpServers

        if provider == .ollama {
            fetchOllamaModels()
        } else if provider == .openAICompatible || provider == .openRouter {
            fetchOpenAIModels()
        }
    }

    internal func fetchOpenRouterModels() {
        fetchOpenAIModels()
    }

    internal func saveSettings() {
        errorMessage = nil
        showingSaveSuccess = false

        let config = LLMConfiguration(
            endpoint: endpoint,
            modelName: modelName,
            utilityModel: utilityModel,
            fastModel: fastModel,
            apiKey: apiKey,
            provider: provider,
            toolFormat: toolFormat,
            mcpServers: mcpServers
        )

        Task {
            do {
                try await llmService.updateConfiguration(config)
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
                let config = LLMConfiguration(
                    endpoint: endpoint,
                    modelName: modelName,
                    utilityModel: utilityModel,
                    fastModel: fastModel,
                    apiKey: apiKey,
                    provider: provider,
                    toolFormat: toolFormat,
                    mcpServers: mcpServers
                )
                try await llmService.updateConfiguration(config)

                _ = try await llmService.sendMessage("Hello")

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
            await llmService.clearConfiguration()
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
                try await llmService.restoreFromBackup()
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
        let currentEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        if !modelName.isEmpty && names.contains(modelName) {
                            // Keep
                        } else if !names.isEmpty {
                            modelName = names[0]
                        }
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
        let currentEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        if !modelName.isEmpty && names.contains(modelName) {
                            // Keep current
                        } else if !names.isEmpty {
                            modelName = names[0]
                        }
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
