import SwiftUI
import MonadCore
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

extension SettingsView {
    internal var backupRestoreSection: some View {
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

    internal func exportConfiguration() {
        Task {
            do {
                let data = try await llmManager.exportConfiguration()

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
                    errorMessage = "Export not yet supported on iOS"
                #endif
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    internal func importConfiguration() {
        #if os(macOS)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false

            if panel.runModal() == .OK, let url = panel.url {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        try await llmManager.importConfiguration(from: data)
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
            errorMessage = "Import not yet supported on iOS"
        #endif
    }
    
    internal func exportDatabase() {
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
    
    internal func importDatabase() {
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
}
