import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var llmService: LLMService
    let persistenceManager: PersistenceManager
    @Environment(\.dismiss) var dismiss

    @State private var endpoint: String = ""
    @State private var modelName: String = ""
    @State private var apiKey: String = ""
    @State private var showingSaveSuccess = false
    @State private var errorMessage: String?
    @State private var showingResetConfirmation = false

    init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
    }

    var body: some View {
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

            // Use Form instead of ScrollView for better macOS compatibility
            Form {
                Section {
                    // Endpoint
                    LabeledContent("API Endpoint") {
                        TextField("https://api.openai.com", text: $endpoint)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Model Name
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

                    // API Key
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Your API key is stored locally and never shared.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("LLM Configuration")
                }

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
                } header: {
                    Text("Backup & Restore")
                } footer: {
                    Text(
                        "Export saves settings without API key. Import will keep your current API key."
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
        .frame(minWidth: 600, minHeight: 600)
        .onAppear {
            endpoint = llmService.configuration.endpoint
            modelName = llmService.configuration.modelName
            apiKey = llmService.configuration.apiKey
        }
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

    // MARK: - Computed Properties

    private var isValid: Bool {
        !endpoint.isEmpty && !modelName.isEmpty && !apiKey.isEmpty
    }

    // MARK: - Actions

    private func saveSettings() {
        errorMessage = nil
        showingSaveSuccess = false

        let config = LLMConfiguration(
            endpoint: endpoint,
            modelName: modelName,
            apiKey: apiKey
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
                    apiKey: apiKey
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
            endpoint = ""
            modelName = ""
            apiKey = ""
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

                // Reload fields
                endpoint = llmService.configuration.endpoint
                modelName = llmService.configuration.modelName
                apiKey = llmService.configuration.apiKey

                showingSaveSuccess = true

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showingSaveSuccess = false
            } catch {
                errorMessage = "Restore failed: \(error.localizedDescription)"
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

                        // Reload fields
                        endpoint = llmService.configuration.endpoint
                        modelName = llmService.configuration.modelName
                        // Keep current API key (not imported for security)
                        apiKey = llmService.configuration.apiKey

                        showingSaveSuccess = true

                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showingSaveSuccess = false
                    } catch {
                        errorMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
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
        persistenceManager: PersistenceManager(persistence: try! .create()))
}
