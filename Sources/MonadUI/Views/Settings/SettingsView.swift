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
    internal let platformContent: PlatformContent

    @State internal var provider: LLMProvider = .openAI
    @State internal var endpoint: String = ""
    @State internal var modelName: String = ""
    @State internal var utilityModel: String = ""
    @State internal var fastModel: String = ""
    @State internal var apiKey: String = ""
    @State internal var toolFormat: ToolCallFormat = .openAI
    @State internal var mcpServers: [MCPServerConfiguration] = []

    @State internal var showingSaveSuccess = false
    @State internal var errorMessage: String?
    @State internal var showingResetConfirmation = false
    @State internal var ollamaModels: [String] = []
    @State internal var openAIModels: [String] = []
    @State internal var isFetchingModels = false

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
            .onChange(of: provider) { _, newValue in
                // Set defaults when switching providers if empty
                switch newValue {
                case .openAI:
                    if endpoint.isEmpty || endpoint.contains("openrouter.ai") {
                        endpoint = "https://api.openai.com"
                    }
                case .openRouter:
                    endpoint = "https://openrouter.ai/api"
                    if modelName.isEmpty || !modelName.contains("/") {
                        modelName = "openai/gpt-4o"
                        utilityModel = "openai/gpt-4o-mini"
                        fastModel = "openai/gpt-4o-mini"
                    }
                case .ollama:
                    if endpoint.isEmpty || endpoint.contains("api.openai.com") {
                        endpoint = "http://localhost:11434"
                    }
                case .openAICompatible:
                    break
                }
            }

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

    // MARK: - Computed Properties

    internal var isValid: Bool {
        if provider == .ollama {
            return !endpoint.isEmpty && !modelName.isEmpty
        }
        return !endpoint.isEmpty && !modelName.isEmpty && !apiKey.isEmpty
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