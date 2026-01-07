import MonadCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

public struct SettingsView<PlatformContent: View>: View {
    public var llmService: LLMService
    public let persistenceManager: PersistenceManager
    @Environment(\.dismiss) var dismiss

    /// Platform-specific configuration sections (like MCP on macOS)
    private let platformContent: PlatformContent

    @State private var provider: LLMProvider = .openAI
    @State private var endpoint: String = ""
    @State private var modelName: String = ""
    @State private var apiKey: String = ""
    @State private var toolFormat: ToolCallFormat = .openAI
    @State private var mcpServers: [MCPServerConfiguration] = []

    @State private var showingSaveSuccess = false
    @State private var errorMessage: String?
    @State private var showingResetConfirmation = false
    @State private var ollamaModels: [String] = []

    public init(
        llmService: LLMService,
        persistenceManager: PersistenceManager,
        @ViewBuilder platformContent: () -> PlatformContent
    ) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.platformContent = platformContent()
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()
                }
                .padding()
                .background(Color.gray.opacity(0.05))

                Form {
                    Section {
                        Picker("Provider", selection: $provider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Tool Format", selection: $toolFormat) {
                            ForEach(ToolCallFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("General")
                    }

                    Section {
                        providerSettings
                    } header: {
                        Text(provider.rawValue + " Configuration")
                    }

                    // Platform specific content (e.g. MCP)
                    platformContent

                    Section {
                        HStack {
                            Image(
                                systemName: llmService.isConfigured
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundColor(llmService.isConfigured ? .green : .red)
                            Text(llmService.isConfigured ? "Connected" : "Not Configured")
                        }
                    } header: {
                        Text("Status")
                    }

                    // Error/Success Messages
                    if let error = errorMessage {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                Spacer()
                                Button("Dismiss") {
                                    errorMessage = nil
                                }
                            }
                        }
                    }

                    if showingSaveSuccess {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Settings saved successfully!")
                            }
                        }
                    }

                    // Action Buttons
                    Section {
                        HStack(spacing: 12) {
                            Button(action: saveSettings) {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text("Save Settings")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isValid)

                            Button(action: testConnection) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Test Connection")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!isValid)
                        }
                    } header: {
                        Text("Save & Test")
                    }

                    // Backup & Restore
                    Section {
                        Button(action: restoreFromBackup) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle")
                                Text("Restore from Backup")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 12) {
                            Button(action: exportConfiguration) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: importConfiguration) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider()
                        
                        HStack(spacing: 12) {
                            Button(action: exportDatabase) {
                                HStack {
                                    Image(systemName: "cylinder.split.1x2")
                                    Text("Export DB")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: importDatabase) {
                                HStack {
                                    Image(systemName: "arrow.down.to.line.compact")
                                    Text("Import DB")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    } header: {
                        Text("Backup & Restore")
                    } footer: {
                        Text(
                            "Export configuration saves settings without API key. Database export saves all chats, memories, and notes as JSON."
                        )
                        .font(.caption)
                    }

                    // Danger Zone
                    Section {
                        Button(action: clearSettings) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear All Settings")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)

                        Button(action: { showingResetConfirmation = true }) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text("Reset Database")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    } header: {
                        Text("Danger Zone")
                    } footer: {
                        Text(
                            "Reset Database will delete ALL conversations, notes, and memories. This cannot be undone!"
                        )
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .formStyle(.grouped)
            }
        }
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 600)
        #endif
        .onAppear(perform: loadSettings)
        .confirmationDialog(
            "Reset Database?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Database", role: .destructive) {
                resetDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will permanently delete ALL conversations, notes, and memories. This action cannot be undone!"
            )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var providerSettings: some View {
        switch provider {
        case .openAI:
            LabeledContent("Model Name") {
                HStack {
                    TextField("gpt-4o", text: $modelName)
                        .textFieldStyle(.roundedBorder)

                    Menu {
                        Button("gpt-4o") { modelName = "gpt-4o" }
                        Button("gpt-4o-mini") { modelName = "gpt-4o-mini" }
                        Button("gpt-4-turbo") { modelName = "gpt-4-turbo" }
                        Button("gpt-3.5-turbo") { modelName = "gpt-3.5-turbo" }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            LabeledContent("API Key") {
                SecureField("", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("API Endpoint") {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.secondary)
            }

        case .openAICompatible:
            LabeledContent("API Endpoint") {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Model Name") {
                TextField("", text: $modelName)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("API Key") {
                SecureField("Required", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

        case .ollama:
            LabeledContent("API Endpoint") {
                HStack {
                    TextField("", text: $endpoint)
                        .textFieldStyle(.roundedBorder)

                    Button("Fetch Models") {
                        fetchOllamaModels()
                    }
                }
            }

            LabeledContent("Model Name") {
                if ollamaModels.isEmpty {
                    TextField("", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $modelName) {
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isValid: Bool {
        if provider == .ollama {
            return !endpoint.isEmpty && !modelName.isEmpty
        }
        return !endpoint.isEmpty && !modelName.isEmpty && !apiKey.isEmpty
    }

    // MARK: - Actions

    private func loadSettings() {
        provider = llmService.configuration.provider
        endpoint = llmService.configuration.endpoint
        modelName = llmService.configuration.modelName
        apiKey = llmService.configuration.apiKey
        toolFormat = llmService.configuration.toolFormat
        mcpServers = llmService.configuration.mcpServers

        if provider == .ollama {
            fetchOllamaModels()
        }
    }

    private func saveSettings() {
        errorMessage = nil
        showingSaveSuccess = false

        let config = LLMConfiguration(
            endpoint: endpoint,
            modelName: modelName,
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

    private func testConnection() {
        errorMessage = nil
        showingSaveSuccess = false

        Task {
            do {
                let config = LLMConfiguration(
                    endpoint: endpoint,
                    modelName: modelName,
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

    private func clearSettings() {
        Task {
            await llmService.clearConfiguration()
            loadSettings()  // Reload defaults
            errorMessage = nil
            showingSaveSuccess = false
        }
    }

    private func restoreFromBackup() {
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

    private func fetchOllamaModels() {
        guard
            let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?
                .appendingPathComponent("api/tags")
        else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // Parse logic: {"models": [{"name": "..."}]}
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let models = json["models"] as? [[String: Any]]
                {

                    let names = models.compactMap { $0["name"] as? String }

                    await MainActor.run {
                        self.ollamaModels = names
                        if !names.contains(modelName) && !names.isEmpty {
                            modelName = names[0]
                        }
                    }
                }
            } catch {
                print("Failed to fetch Ollama models: \(error)")
            }
        }
    }

    private func exportConfiguration() {
        Task {
            do {
                let data = try await llmService.exportConfiguration()

                #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "monad-config.json"

                    if panel.runModal() == .OK, let url = panel.url {
                        try data.write(to: url)
                        showingSaveSuccess = true

                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showingSaveSuccess = false
                    }
                #else
                    // iOS Export implementation (e.g. ShareSheet)
                    errorMessage = "Export not yet supported on iOS"
                #endif
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importConfiguration() {
        #if os(macOS)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false

            if panel.runModal() == .OK, let url = panel.url {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        try await llmService.importConfiguration(from: data)
                        loadSettings()
                        showingSaveSuccess = true

                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showingSaveSuccess = false
                    } catch {
                        errorMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        #else
            // iOS Import implementation
            errorMessage = "Import not yet supported on iOS"
        #endif
    }
    
    private func exportDatabase() {
        Task {
            do {
                let data = try await persistenceManager.exportDatabase()

                #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "monad-database-backup.json"

                    if panel.runModal() == .OK, let url = panel.url {
                        try data.write(to: url)
                        showingSaveSuccess = true

                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showingSaveSuccess = false
                    }
                #else
                    errorMessage = "Export not yet supported on iOS"
                #endif
            } catch {
                errorMessage = "Database export failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func importDatabase() {
        #if os(macOS)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.message = "This will overwrite your existing database!"

            if panel.runModal() == .OK, let url = panel.url {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        try await persistenceManager.importDatabase(from: data)
                        showingSaveSuccess = true

                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showingSaveSuccess = false
                    } catch {
                        errorMessage = "Database import failed: \(error.localizedDescription)"
                    }
                }
            }
        #else
            errorMessage = "Import not yet supported on iOS"
        #endif
    }

    private func resetDatabase() {
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

#Preview {
    SettingsView(
        llmService: LLMService(),
        persistenceManager: PersistenceManager(persistence: try! PersistenceService.create())
    ) {
        EmptyView()
    }
}
