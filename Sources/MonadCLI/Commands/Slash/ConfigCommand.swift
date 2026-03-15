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
              format        Tool calling format (openai, native, json, xml)

            \(TerminalUI.bold("Examples:"))
              /config set model gpt-4o
              /config set api-key
              /config provider openrouter
              /config set format json

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
                print("  \(TerminalUI.dim("Tool Format:"))  \(providerConfig.toolFormat.rawValue)")
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
        "tool-format": "format", "format": "format"
    ]

    private func applyConfigValue(
        key: String,
        value: String,
        config: inout LLMConfiguration
    ) -> Bool {
        let normalizedKey = Self.configKeyMapping[key.lowercased()] ?? key.lowercased()

        switch normalizedKey {
        case "apiKey":
            config.apiKey = value
        case "model":
            config.modelName = value
        case "utility":
            config.utilityModel = value
        case "fast":
            config.fastModel = value
        case "endpoint":
            config.endpoint = value
        case "memory", "document":
            return applyIntegerLimit(normalizedKey, value: value, config: &config)
        case "format":
            guard let format = parseToolFormat(value) else { return false }
            config.toolFormat = format
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

    private func parseToolFormat(_ value: String) -> ToolCallFormat? {
        switch value.lowercased() {
        case "openai", "native": return .openAI
        case "json": return .json
        case "xml": return .xml
        default:
            TerminalUI.printError("Unknown tool format: \(value)")
            print("  Available: openai, native, json, xml")
            return nil
        }
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
        print("Enter value for \(key): ", terminator: "")
        guard let value = readLine()?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
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
        print("Endpoint [\(providerConfig.endpoint)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            providerConfig.endpoint = input
        }

        // API Key
        print("API Key [\(maskApiKey(providerConfig.apiKey))]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            providerConfig.apiKey = input
        }

        // Model
        print("Model [\(providerConfig.modelName)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            providerConfig.modelName = input
        }

        // Utility Model
        let utilityDisplay =
            providerConfig.utilityModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.utilityModel
        print("Utility Model [\(utilityDisplay)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            providerConfig.utilityModel = input
        }

        // Fast Model
        let fastDisplay =
            providerConfig.fastModel == providerConfig.modelName
                ? "(same as model)" : providerConfig.fastModel
        print("Fast Model [\(fastDisplay)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            providerConfig.fastModel = input
        }

        // Memory Limit
        print("Memory Limit [\(config.memoryContextLimit)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            if let limit = Int(input) {
                config.memoryContextLimit = limit
            }
        }

        // Document Limit
        print("Document Limit [\(config.documentContextLimit)]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            if let limit = Int(input) {
                config.documentContextLimit = limit
            }
        }

        // Tool Format
        promptToolFormat(providerConfig: &providerConfig)
    }

    func promptToolFormat(providerConfig: inout ProviderConfiguration) {
        print("\nSelect Tool Calling Format:")
        let toolFormats = ToolCallFormat.allCases
        for (index, format) in toolFormats.enumerated() {
            let isDefault = format == providerConfig.toolFormat ? " (current)" : ""
            print("\(index + 1). \(format.rawValue)\(isDefault)")
        }
        print("Selection [1-\(toolFormats.count), Enter to skip]: ", terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            if let idx = Int(input), idx >= 1, idx <= toolFormats.count {
                providerConfig.toolFormat = toolFormats[idx - 1]
            }
        }
    }
}
