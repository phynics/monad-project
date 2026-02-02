import MonadCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

public struct SettingsView<PlatformContent: View>: View {
    public var llmManager: LLMManager
    public let persistenceManager: PersistenceManager
    @Environment(\.dismiss) var dismiss

    /// Platform-specific configuration sections (like MCP on macOS)
    internal let platformContent: PlatformContent

    @State internal var workingConfig: LLMConfiguration = .openAI
    @State internal var selectedProvider: LLMProvider = .openAI
    
    // UI State for feedback
    @State internal var showingSaveSuccess = false
    @State internal var errorMessage: String?
    @State internal var showingResetConfirmation = false
    @State internal var ollamaModels: [String] = []
    @State internal var openAIModels: [String] = []
    @State internal var isFetchingModels = false

    public init(
        llmManager: LLMManager,
        persistenceManager: PersistenceManager,
        @ViewBuilder platformContent: () -> PlatformContent
    ) {
        self.llmManager = llmManager
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
            // Active Provider Picker (Global setting)
            Picker("Active Provider", selection: $workingConfig.activeProvider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            // Configuration Provider Picker (What we are editing)
            Picker("Edit Configuration For", selection: $selectedProvider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProvider) { _, newValue in
                // Refresh models when switching view if needed
                if newValue == .ollama && ollamaModels.isEmpty {
                    fetchOllamaModels()
                }
            }

            Picker("Tool Format", selection: currentProviderBinding.toolFormat) {
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
            Text(selectedProvider.rawValue + " Configuration")
        }
    }
    
    private var statusSection: some View {
        Section {
            HStack {
                Image(
                    systemName: llmManager.isConfigured
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundColor(llmManager.isConfigured ? .green : .red)
                Text(llmManager.isConfigured ? "Connected" : "Not Configured")
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

    internal var currentProviderBinding: Binding<ProviderConfiguration> {
        Binding(
            get: { workingConfig.providers[selectedProvider] ?? ProviderConfiguration.defaultFor(selectedProvider) },
            set: { workingConfig.providers[selectedProvider] = $0 }
        )
    }

    internal var isValid: Bool {
        guard let config = workingConfig.providers[selectedProvider] else { return false }
        if selectedProvider == .ollama {
            return !config.endpoint.isEmpty && !config.modelName.isEmpty
        }
        return !config.endpoint.isEmpty && !config.modelName.isEmpty && !config.apiKey.isEmpty
    }
}
