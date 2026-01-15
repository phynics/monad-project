import MonadCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

public struct SettingsView<PlatformContent: View>: View {
    public var llmService: any LLMServiceProtocol
    public let persistenceManager: PersistenceManager
    public var chatViewModel: ChatViewModel? = nil
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
        llmService: any LLMServiceProtocol,
        persistenceManager: PersistenceManager,
        chatViewModel: ChatViewModel? = nil,
        @ViewBuilder platformContent: () -> PlatformContent
    ) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.chatViewModel = chatViewModel
        self.platformContent = platformContent()
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        generalSection
                        providerConfigSection
                        platformContent
                        statusSection
                        messageSection
                        saveTestSection
                        backupRestoreSection
                        dangerZoneSection
                    }
                    .padding()
                }
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
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Picker("Connection Mode", selection: $workingConfig.connectionMode) {
                    ForEach(LLMConfiguration.ConnectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Group {
                    if workingConfig.connectionMode == .remote {
                        Text("Monad Assistant connects to a centralized Monad Server. Logic and memory are handled remotely.")
                    } else {
                        Text("Monad Assistant runs purely on this device. Logic and memory are stored locally.")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            if workingConfig.connectionMode == .remote {
                remoteServerSettings
            }
            
            Divider()

            // Active Provider Picker (Global setting)
            if workingConfig.connectionMode == .local {
                HStack {
                    Text("Active Provider")
                    Spacer()
                    Picker("", selection: $workingConfig.activeProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            
            if workingConfig.connectionMode == .local {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration Target").font(.subheadline).foregroundStyle(.secondary)
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
                }

                HStack {
                    Text("Tool Format")
                    Spacer()
                    Picker("", selection: currentProviderBinding.toolFormat) {
                        ForEach(ToolCallFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }
    
    @ViewBuilder
    private var remoteServerSettings: some View {
        VStack(spacing: 12) {
            LabeledContent("Server Host") {
                TextField("localhost", text: $workingConfig.monadServer.host)
                    .textFieldStyle(.roundedBorder)
            }
            
            LabeledContent("Server Port") {
                TextField("50051", value: $workingConfig.monadServer.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
            }
            
            Toggle("Use TLS", isOn: $workingConfig.monadServer.useTLS)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
   
    @ViewBuilder
    private var providerConfigSection: some View {
        // Only show if Local mode
        if workingConfig.connectionMode == .local {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedProvider.rawValue + " Configuration").font(.headline)
                providerSettings
            }
        } else {
            EmptyView()
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status").font(.headline)
            HStack {
                Image(
                    systemName: llmService.isConfigured
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundColor(llmService.isConfigured ? .green : .red)
                Text(llmService.isConfigured ? "Connected" : "Not Configured")
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var messageSection: some View {
        if let error = errorMessage {
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
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }

        if showingSaveSuccess {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Settings saved successfully!")
            }
            .padding(8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var saveTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions").font(.headline)
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
                .controlSize(.large)

                Button(action: testConnection) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isValid)
                .controlSize(.large)
            }
        }
    }
    
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone").font(.headline).foregroundColor(.red)
            
            VStack(spacing: 12) {
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
                
                Text(
                    "Reset Database will delete ALL conversations, notes, and memories. This cannot be undone!"
                )
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding()
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)
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

#Preview {
    SettingsView(
        llmService: LLMService(),
        persistenceManager: PersistenceManager(persistence: try! PersistenceService.create())
    ) {
        EmptyView()
    }
}
