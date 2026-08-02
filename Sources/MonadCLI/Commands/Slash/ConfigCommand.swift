import Foundation
import MonadClient

struct ConfigCommand: SlashCommand {
    let name = "config"
    let description = "View or edit configuration"
    let category: String? = "Configuration"
    let usage = "/config [show|set|provider|edit]"

    func run(args: [String], context: ChatContext) async throws {
        // Default to interactive edit if no args
        let subcommand = args.first ?? "edit"

        switch subcommand {
        case "show", "view":
            await showConfig(context: context)
        case "set":
            if args.count >= 3 {
                await setConfig(
                    key: args[1], value: args.dropFirst(2).joined(separator: " "), context: context
                )
            } else if args.count == 2 {
                await setConfigWithPrompt(key: args[1], context: context)
            } else {
                printConfigHelp()
            }
        case "provider":
            if args.count > 1 {
                await setProvider(args[1], context: context)
            } else {
                TerminalUI.printError(
                    "Usage: /config provider <openai|openrouter|ollama|compatible>"
                )
            }
        case "edit":
            await interactiveConfigEdit(context: context)
        case "help":
            printConfigHelp()
        default:
            if args.isEmpty {
                await interactiveConfigEdit(context: context)
            } else {
                printConfigHelp()
            }
        }
    }

    private func printConfigHelp() {
        print(
            """

            \(TerminalUI.bold("Config Commands:"))
              /config                   Interactive configuration editor
              /config show              Show current configuration
              /config edit              Interactive configuration editor
              /config set <key> <value> Set a specific value
              /config set <key>         Prompt for value
              /config provider <name>   Switch provider

            \(TerminalUI.bold("Available Keys:"))
              api-key       API key for the provider
              model         Main model name
              utility       Utility model (for summaries, etc.)
              fast          Fast model (for quick responses)
              endpoint      API endpoint URL
              memory        Memory context limit (number)
              document      Document context limit (number)

            \(TerminalUI.bold("Examples:"))
              /config set model gpt-4o
              /config set api-key
              /config provider openrouter

            """
        )
    }

    private func showConfig(context: ChatContext) async {
        do {
            let config = try await context.client.getConfiguration()

            print("\n\(TerminalUI.bold("LLM Configuration"))\n")
            print("  \(TerminalUI.dim("Provider:"))     \(config.activeProvider.rawValue)")

            if let providerConfig = config.providers[config.activeProvider] {
                print("  \(TerminalUI.dim("Endpoint:"))     \(providerConfig.endpoint)")
                print("  \(TerminalUI.dim("API Key:"))      \(maskApiKey(providerConfig.apiKey))")
                print("  \(TerminalUI.dim("Model:"))        \(providerConfig.modelName)")
                print("  \(TerminalUI.dim("Utility:"))      \(providerConfig.utilityModel)")
                print("  \(TerminalUI.dim("Fast:"))         \(providerConfig.fastModel)")
            }

            print("")
            print("  \(TerminalUI.dim("Memory Limit:"))   \(config.memoryContextLimit)")
            print("  \(TerminalUI.dim("Document Limit:")) \(config.documentContextLimit)")
            print("")
            print("  \(TerminalUI.dim("Valid:"))          \(config.isValid ? "✓" : "✗")")
            print("")
        } catch {
            TerminalUI.printError("Failed to get configuration: \(error.localizedDescription)")
        }
    }

    private func maskApiKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Config Key Mapping

    private static let configKeyMapping: [String: String] = [
        "api-key": "apiKey", "apikey": "apiKey", "key": "apiKey",
        "model": "model",
        "utility-model": "utility", "utility": "utility",
        "fast-model": "fast", "fast": "fast",
        "endpoint": "endpoint", "url": "endpoint",
        "memory-limit": "memory", "memory": "memory",
        "document-limit": "document", "document": "document",
    ]

    private func applyConfigValue(
        key: String,
        value: String,
        config: inout LLMConfiguration
    ) -> Bool {
        let normalizedKey = Self.configKeyMapping[key.lowercased()] ?? key.lowercased()

        switch normalizedKey {
        case "apiKey":
            config.providers[config.activeProvider]?.apiKey = value
        case "model":
            config.providers[config.activeProvider]?.modelName = value
        case "utility":
            config.providers[config.activeProvider]?.utilityModel = value
        case "fast":
            config.providers[config.activeProvider]?.fastModel = value
        case "endpoint":
            config.providers[config.activeProvider]?.endpoint = value
        case "memory", "document":
            return applyIntegerLimit(normalizedKey, value: value, config: &config)
        default:
            TerminalUI.printError("Unknown config key: \(key)")
            return false
        }
        return true
    }

    private func applyIntegerLimit(_ key: String, value: String, config: inout LLMConfiguration) -> Bool {
        guard let limit = Int(value) else {
            TerminalUI.printError("Invalid number: \(value)")
            return false
        }
        if key == "memory" {
            config.memoryContextLimit = limit
        } else {
            config.documentContextLimit = limit
        }
        return true
    }

    private func setConfig(key: String, value: String, context: ChatContext) async {
        do {
            var config = try await context.client.getConfiguration()
            guard applyConfigValue(key: key, value: value, config: &config) else { return }
            try await context.client.updateConfiguration(config)
            TerminalUI.printSuccess("Updated \(key) = \(key.contains("key") ? "***" : value)")
        } catch {
            TerminalUI.printError("Failed to update config: \(error.localizedDescription)")
        }
    }

    private func setConfigWithPrompt(key: String, context: ChatContext) async {
        guard let value = CLIInput.readLine(prompt: "Enter value for \(key): "), !value.isEmpty else {
            TerminalUI.printError("No value provided")
            return
        }
        await setConfig(key: key, value: value, context: context)
    }

    private func setProvider(_ name: String, context: ChatContext) async {
        let provider: LLMProvider
        switch name.lowercased() {
        case "openai": provider = .openAI
        case "openrouter": provider = .openRouter
        case "ollama": provider = .ollama
        case "compatible", "openai-compatible": provider = .openAICompatible
        default:
            TerminalUI.printError("Unknown provider: \(name)")
            print("  Available: openai, openrouter, ollama, compatible")
            return
        }

        do {
            var config = try await context.client.getConfiguration()
            config.activeProvider = provider
            try await context.client.updateConfiguration(config)
            TerminalUI.printSuccess("Switched to \(provider.rawValue)")
        } catch {
            TerminalUI.printError("Failed to switch provider: \(error.localizedDescription)")
        }
    }
}

// MARK: - Interactive Config Editor

private extension ConfigCommand {
    func interactiveConfigEdit(context: ChatContext) async {
        do {
            var config = try await context.client.getConfiguration()
            guard var providerConfig = config.providers[config.activeProvider] else {
                TerminalUI.printError("No provider configuration found")
                return
            }

            print("\n\(TerminalUI.bold("Configuration Editor"))")
            print(TerminalUI.dim("Press Enter to keep current value, or type new value"))
            print("")

            promptAndUpdateFields(config: &config, providerConfig: &providerConfig)

            // Save
            config.providers[config.activeProvider] = providerConfig
            try await context.client.updateConfiguration(config)
            print("")
            TerminalUI.printSuccess("Configuration updated!")

        } catch {
            TerminalUI.printError("Failed to update config: \(error.localizedDescription)")
        }
    }

    func promptAndUpdateFields(
        config: inout LLMConfiguration,
        providerConfig: inout ProviderConfiguration
    ) {
        // Endpoint
        if let input = CLIInput.readLine(prompt: "Endpoint [\(providerConfig.endpoint)]: "), !input.isEmpty {
            providerConfig.endpoint = input
        }

        // API Key
        if let input = CLIInput.readLine(prompt: "API Key [\(maskApiKey(providerConfig.apiKey))]: "), !input.isEmpty {
            providerConfig.apiKey = input
        }

        // Model
        if let input = CLIInput.readLine(prompt: "Model [\(providerConfig.modelName)]: "), !input.isEmpty {
            providerConfig.modelName = input
        }

        // Utility Model
        let utilityDisplay =
            providerConfig.utilityModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.utilityModel
        if let input = CLIInput.readLine(prompt: "Utility Model [\(utilityDisplay)]: "), !input.isEmpty {
            providerConfig.utilityModel = input
        }

        // Fast Model
        let fastDisplay =
            providerConfig.fastModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.fastModel
        if let input = CLIInput.readLine(prompt: "Fast Model [\(fastDisplay)]: "), !input.isEmpty {
            providerConfig.fastModel = input
        }

        // Memory Limit
        if let input = CLIInput.readLine(prompt: "Memory Limit [\(config.memoryContextLimit)]: "), !input.isEmpty {
            if let limit = Int(input) {
                config.memoryContextLimit = limit
            }
        }

        // Document Limit
        if let input = CLIInput.readLine(prompt: "Document Limit [\(config.documentContextLimit)]: "), !input.isEmpty {
            if let limit = Int(input) {
                config.documentContextLimit = limit
            }
        }
    }
}
