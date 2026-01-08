import MonadCore
import SwiftUI

struct MessageDebugResponseView: View {
    let debugInfo: MessageDebugInfo
    
    var body: some View {
        // Assistant message: API metadata
        if let apiResponse = debugInfo.apiResponse {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let model = apiResponse.model {
                        InfoRow(label: "Model", value: model)
                    }
                    if let promptTokens = apiResponse.promptTokens {
                        InfoRow(label: "Prompt Tokens", value: "\(promptTokens)")
                    }
                    if let completionTokens = apiResponse.completionTokens {
                        InfoRow(
                            label: "Completion Tokens", value: "\(completionTokens)")
                    }
                    if let totalTokens = apiResponse.totalTokens {
                        InfoRow(label: "Total Tokens", value: "\(totalTokens)")
                    }
                    if let finishReason = apiResponse.finishReason {
                        InfoRow(label: "Finish Reason", value: finishReason)
                    }
                    if let fingerprint = apiResponse.systemFingerprint {
                        InfoRow(label: "System Fingerprint", value: fingerprint)
                    }
                }
            } header: {
                SectionHeader(title: "Debug: API Response")
            }
        }

        // Assistant message: Original response
        if let original = debugInfo.originalResponse {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Original Response")
                            .font(.headline)
                        Spacer()
                        Button("Copy") {
                            #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    original, forType: .string)
                            #else
                                UIPasteboard.general.string = original
                            #endif
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(original)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                SectionHeader(title: "Debug: Original Message")
            }
        }

        // Assistant message: Parsed content
        if let parsed = debugInfo.parsedContent {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Parsed Content")
                            .font(.headline)
                        Spacer()
                        Button("Copy") {
                            #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(parsed, forType: .string)
                            #else
                                UIPasteboard.general.string = parsed
                            #endif
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(parsed)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                SectionHeader(title: "Debug: Parsed Message")
            }
        }

        // Assistant message: Parsed thinking
        if let thinking = debugInfo.parsedThinking {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thinking Block")
                            .font(.headline)
                        Spacer()
                        Button("Copy") {
                            #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    thinking, forType: .string)
                            #else
                                UIPasteboard.general.string = thinking
                            #endif
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(thinking)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                SectionHeader(title: "Debug: Thinking Block")
            }
        }
    }
}
