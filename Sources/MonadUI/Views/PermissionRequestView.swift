import SwiftUI
import MonadCore

struct PermissionRequestView: View {
    let request: ChatViewModel.PermissionRequest
    let onResponse: (PermissionResponse) -> Void

    // Helper to find path in arguments
    private var detectedPathKey: String? {
        let keys = ["path", "filename", "file", "directory", "root"]
        for key in keys {
            if request.arguments.keys.contains(key) {
                return key
            }
        }
        return nil
    }

    private var detectedPath: String? {
        guard let key = detectedPathKey else { return nil }
        return request.arguments[key]
    }

    // Helper to get directory to allow
    private var directoryToAllow: String? {
        guard let path = detectedPath else { return nil }

        let absolutePath: String
        if path.hasPrefix("/") {
            absolutePath = path
        } else if path.hasPrefix("~") {
            absolutePath = (path as NSString).expandingTildeInPath
        } else {
            absolutePath = URL(fileURLWithPath: request.workingDirectory).appendingPathComponent(path).standardized.path
        }

        let url = URL(fileURLWithPath: absolutePath)
        return url.deletingLastPathComponent().path
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Permission Requested")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                Text("Tool: **\(request.tool.name)**")
                Text("Description: \(request.tool.description)")

                if let path = detectedPath {
                    Text("Path: `\(path)`")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }

                if !request.arguments.isEmpty {
                    Text("Arguments:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(request.arguments.keys.sorted(), id: \.self) { key in
                        if key != detectedPathKey, let value = request.arguments[key] {
                            Text("- **\(key)**: \(value)")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .secondarySystemBackground))
            #endif
            .cornerRadius(12)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    onResponse(.deny)
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    onResponse(.approve)
                } label: {
                    Text("Allow Once")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: [])

                if let dir = directoryToAllow {
                    Button {
                        onResponse(.approveForSession(path: dir))
                    } label: {
                        VStack(spacing: 2) {
                            Text("Allow for Session")
                            Text("in \(dir.hasSuffix("/") ? dir : dir + "/")")
                                .font(.caption2)
                                .opacity(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    onResponse(.approveForSession(path: request.workingDirectory))
                } label: {
                    VStack(spacing: 2) {
                        Text("Allow Session (PWD)")
                        Text("in \(request.workingDirectory)")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top)
        }
        .padding(30)
        .frame(width: 500)
    }
}
