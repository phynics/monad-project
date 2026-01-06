import MonadCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

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
                        
                        // Context Generation Info
                        if let tags = debugInfo.generatedTags, !tags.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Generated Tags:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    FlowLayout(spacing: 4) {
                                        ForEach(tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.1))
                                                .foregroundColor(.orange)
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    if let vector = debugInfo.queryVector, !vector.isEmpty {
                                        Divider()
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Query Embedding Vector (\(vector.count) dims):")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                            Text(vector.prefix(8).map { String(format: "%.3f", $0) }.joined(separator: ", ") + "...")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(8)
                            } header: {
                                SectionHeader(title: "Debug: Context Generation")
                            }
                            
                            Divider()
                        }
                        
                        // Context Memories Section
                        if let results = debugInfo.contextMemories, !results.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(results, id: \.memory.id) { result in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(result.memory.title)
                                                    .font(.headline)
                                                Spacer()
                                                if let similarity = result.similarity {
                                                    Text(String(format: "%.1f%% Match", similarity * 100))
                                                        .font(.caption)
                                                        .foregroundStyle(.blue)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.blue.opacity(0.1))
                                                        .cornerRadius(4)
                                                } else {
                                                    Text("Keyword Match")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            
                                            Text(result.memory.content)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                            
                                            if !result.memory.tagArray.isEmpty {
                                                Text(result.memory.tagArray.joined(separator: ", "))
                                                    .font(.caption2)
                                                    .italic()
                                            }
                                            
                                            // Embedding Info
                                            let vector = result.memory.embeddingVector
                                            if !vector.isEmpty {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Embedding Vector (\(vector.count) dims):")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(.secondary)
                                                    Text(vector.prefix(8).map { String(format: "%.3f", $0) }.joined(separator: ", ") + "...")
                                                        .font(.system(size: 8, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.top, 4)
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.blue.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                }
                            } header: {
                                SectionHeader(title: "Debug: Context Memories")
                            }
                            
                            Divider()
                        }
                        
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Full Raw Prompt")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") {
                                        #if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(
                                                rawPrompt, forType: .string)
                                        #else
                                            UIPasteboard.general.string = rawPrompt
                                        #endif
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
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
        #endif
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
