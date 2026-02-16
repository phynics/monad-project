import MonadShared
import Darwin
import Foundation
import MonadClient

struct ConfigurationScreen {
    let client: MonadClient

    func show() async throws {
        TerminalUI.printInfo("Server is not configured.")
        print(TerminalUI.bold("Configuration Wizard"))

        // Select Provider
        print("\nSelect LLM Provider:")
        let providers = LLMProvider.allCases
        for (index, provider) in providers.enumerated() {
            print("\(index + 1). \(provider.rawValue)")
        }

        let providerIndex = readInt(min: 1, max: providers.count) - 1
        let selectedProvider = providers[providerIndex]

        // Defaults
        var config = ProviderConfiguration.defaultFor(selectedProvider)

        // Customize
        print("\nConfiguring \(selectedProvider.rawValue):")

        config.endpoint = readString(
            prompt: "Endpoint URL [\(config.endpoint)]:", default: config.endpoint)

        // Only ask for API Key if not Ollama (or if user wants to override)
        // Generally Ollama doesn't need key, but some setups might
        if selectedProvider != .ollama {
            config.apiKey = readSecret(prompt: "API Key:")
        }

        config.modelName = readString(
            prompt: "Model Name [\(config.modelName)]:", default: config.modelName)

        // Utility model (empty = use main model)
        let utilityDefault = config.utilityModel == config.modelName ? "" : config.utilityModel
        let utilityInput = readString(
            prompt: "Utility Model (empty = use main) [\(utilityDefault)]:", default: utilityDefault
        )
        config.utilityModel = utilityInput.isEmpty ? config.modelName : utilityInput

        // Fast model (empty = use main model)
        let fastDefault = config.fastModel == config.modelName ? "" : config.fastModel
        let fastInput = readString(
            prompt: "Fast Model (empty = use main) [\(fastDefault)]:", default: fastDefault)
        config.fastModel = fastInput.isEmpty ? config.modelName : fastInput

        // Tool Format selection
        print("\nSelect Tool Calling Format:")
        let toolFormats = ToolCallFormat.allCases
        for (index, format) in toolFormats.enumerated() {
            let isDefault = format == config.toolFormat ? " (current)" : ""
            print("\(index + 1). \(format.rawValue)\(isDefault)")
        }
        let formatIndex = readInt(min: 1, max: toolFormats.count) - 1
        config.toolFormat = toolFormats[formatIndex]

        // Update Config
        // We initialize LLMConfiguration with the active provider
        var llmConfig = LLMConfiguration(activeProvider: selectedProvider)

        // We override the default provider config with our customized one
        llmConfig.providers[selectedProvider] = config

        TerminalUI.printLoading("Updating configuration...")
        do {
            try await client.updateConfiguration(llmConfig)
            TerminalUI.printSuccess("Configuration updated successfully!")
        } catch {
            TerminalUI.printError("Failed to update config: \(error.localizedDescription)")
            throw error
        }
    }

    private func readString(prompt: String, default defaultValue: String? = nil) -> String {
        print(prompt, terminator: " ")
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            return input
        }
        return defaultValue ?? ""
    }

    private func readInt(min: Int, max: Int) -> Int {
        while true {
            print("Selection [\(min)-\(max)]:", terminator: " ")
            if let input = readLine(), let val = Int(input), val >= min && val <= max {
                return val
            }
            TerminalUI.printError("Invalid selection.")
        }
    }

    private func readSecret(prompt: String) -> String {
        print(prompt, terminator: "")  // getpass handles its own prompt but usually no terminator control?
        // Actually getpass prints prompt.
        // But readLine prints newline.
        // Let's rely on getpass ONLY.

        // C-string prompt
        return prompt.withCString { ptr in
            guard let pass = getpass(ptr) else { return "" }
            return String(cString: pass)
        }
    }
}
