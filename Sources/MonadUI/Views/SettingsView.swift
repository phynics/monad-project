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
    @State private var utilityModel: String = ""
    @State private var fastModel: String = ""
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
                headerView
                
                Form {
                    generalSection
                    providerConfigSection
                    platformContent
                    statusSection
                    messageSection
                    saveTestSection
                    backupRestoreSection
                    dangerZoneSection
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

    // MARK: - Sections
    
    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private var generalSection: some View {
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
    }
    
    private var providerConfigSection: some View {
        Section {
            providerSettings
        } header: {
            Text(provider.rawValue + " Configuration")
        }
    }
    
    private var statusSection: some View {
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
    }
    
    @ViewBuilder
    private var messageSection: some View {
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
    }
    
    private var saveTestSection: some View {
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
    }
    
    private var backupRestoreSection: some View {
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
    }
    
    private var dangerZoneSection: some View {
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

    // MARK: - Subviews

    @ViewBuilder
    private var providerSettings: some View {
        switch provider {
        case .openAI:
            openAISettings
        case .openAICompatible:
            openAICompatibleSettings
        case .ollama:
            ollamaSettings
        }
    }
    
    @ViewBuilder
    private var openAISettings: some View {
        Group {
            LabeledContent("Model Name (Main)") {
                HStack {
                    TextField("gpt-4o", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $modelName)
                }
            }
            
            LabeledContent("Utility Model") {
                HStack {
                    TextField("gpt-4o-mini", text: $utilityModel)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $utilityModel)
                }
            }
            
            LabeledContent("Fast Model") {
                HStack {
                    TextField("gpt-4o-mini", text: $fastModel)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $fastModel)
                }
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
    }
    
    @ViewBuilder
    private var openAICompatibleSettings: some View {
        LabeledContent("API Endpoint") {
            TextField("", text: $endpoint)
                .textFieldStyle(.roundedBorder)
        }

        LabeledContent("Model Name") {
            TextField("", text: $modelName)
                .textFieldStyle(.roundedBorder)
        }
        
        LabeledContent("Utility Model") {
            TextField("", text: $utilityModel)
                .textFieldStyle(.roundedBorder)
        }
        
        LabeledContent("Fast Model") {
            TextField("", text: $fastModel)
                .textFieldStyle(.roundedBorder)
        }

        LabeledContent("API Key") {
            SecureField("Required", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    @ViewBuilder
    private var ollamaSettings: some View {
        LabeledContent("API Endpoint") {
            HStack {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)

                Button("Fetch Models") {
                    fetchOllamaModels()
                }
            }
        }

        Group {
            ollamaModelPicker("Model Name (Main)", selection: $modelName)
            ollamaModelPicker("Utility Model", selection: $utilityModel)
            ollamaModelPicker("Fast Model", selection: $fastModel)
        }
    }
    
    private func modelMenu(binding: Binding<String>) -> some View {
        Menu {
            Button("gpt-4o") { binding.wrappedValue = "gpt-4o" }
            Button("gpt-4o-mini") { binding.wrappedValue = "gpt-4o-mini" }
            Button("gpt-4-turbo") { binding.wrappedValue = "gpt-4-turbo" }
            Button("gpt-3.5-turbo") { binding.wrappedValue = "gpt-3.5-turbo" }
        } label: {
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    @ViewBuilder
    private func ollamaModelPicker(_ label: String, selection: Binding<String>) -> some View {
        LabeledContent(label) {
            if ollamaModels.isEmpty {
                TextField("", text: selection)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: selection) {
                    ForEach(ollamaModels, id: \.self) { model in
                        Text(model).tag(model)
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
        utilityModel = llmService.configuration.utilityModel
        fastModel = llmService.configuration.fastModel
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

    private func testConnection() {
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
        let currentEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentEndpoint.isEmpty else { return }
        
        Task {
            do {
                // Create a temporary client with the current input endpoint to fetch models
                let tempClient = OllamaClient(endpoint: currentEndpoint, modelName: "temp")
                if let names = try await tempClient.fetchAvailableModels() {
                    await MainActor.run {
                        self.ollamaModels = names
                        if !names.contains(modelName) && !names.isEmpty {
                            modelName = names[0]
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch models: \(error.localizedDescription)"
                }
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
