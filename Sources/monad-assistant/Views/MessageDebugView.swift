import SwiftUI
import AppKit

/// Simple debug view for message details
struct MessageDebugView: View {
    let message: Message
    let debugInfo: MessageDebugInfo
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Message info
                    Section {
                        InfoRow(label: "Role", value: message.role.rawValue.capitalized)
                        InfoRow(label: "Timestamp", value: message.timestamp.formatted())
                        if let think = message.think {
                            InfoRow(label: "Has Thinking", value: "Yes (\(think.count) chars)")
                        }
                    } header: {
                        SectionHeader(title: "Message Info")
                    }
                    
                    Divider()
                    
                    // User message: Raw prompt
                    if let rawPrompt = debugInfo.rawPrompt {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Full Raw Prompt")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(rawPrompt, forType: .string)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                ScrollView {
                                    Text(rawPrompt)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 300)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        } header: {
                            SectionHeader(title: "Debug: User Message")
                        }
                    }
                    
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
                                    InfoRow(label: "Completion Tokens", value: "\(completionTokens)")
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
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(original, forType: .string)
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
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(parsed, forType: .string)
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
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(thinking, forType: .string)
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
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Message Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
