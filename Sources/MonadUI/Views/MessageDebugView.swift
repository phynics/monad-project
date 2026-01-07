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
                        
                        // Context Generation Pipeline
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                // Step 1: Augmentation
                                PipelineStepView(
                                    step: "1", 
                                    title: "Query Augmentation", 
                                    description: "Augmenting user query with recent history for better context."
                                )
                                if let augmented = debugInfo.augmentedQuery {
                                    Text(augmented)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(6)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                } else {
                                    Text("No history available for augmentation.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                // Step 2: Tag Generation
                                PipelineStepView(
                                    step: "2", 
                                    title: "Tag & Vector Generation", 
                                    description: "Extracting keywords and generating embedding vector."
                                )
                                if let tags = debugInfo.generatedTags, !tags.isEmpty {
                                    FlowLayout(spacing: 4) {
                                        ForEach(tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.1))
                                                .foregroundColor(.orange)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                
                                if let vector = debugInfo.queryVector, !vector.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Embedding Vector (\(vector.count) dims):")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(vector.prefix(8).map { String(format: "%.3f", $0) }.joined(separator: ", ") + "...")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                // Step 3: Semantic Search
                                PipelineStepView(
                                    step: "3", 
                                    title: "Semantic Search", 
                                    description: "Vector similarity search in local database (Top 5 candidates)."
                                )
                                if let semantic = debugInfo.semanticResults, !semantic.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(semantic, id: \.memory.id) { result in
                                            HStack {
                                                Text("• \(result.memory.title)")
                                                    .font(.caption)
                                                Spacer()
                                                Text(String(format: "%.1f%%", (result.similarity ?? 0) * 100))
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                } else {
                                    Text("No semantic matches found.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                // Step 4: Tag Search
                                PipelineStepView(
                                    step: "4", 
                                    title: "Keyword Search", 
                                    description: "Searching memories matching generated tags."
                                )
                                if let tagMatches = debugInfo.tagResults, !tagMatches.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(tagMatches) { match in
                                            Text("• \(match.title)")
                                                .font(.caption)
                                        }
                                    }
                                } else {
                                    Text("No keyword matches found.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                // Step 5: Final Ranking
                                PipelineStepView(
                                    step: "5", 
                                    title: "Ranking & Selection", 
                                    description: "Combining results, re-calculating similarity, and picking Top 3."
                                )
                                if let results = debugInfo.contextMemories, !results.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(results, id: \.memory.id) { result in
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text(result.memory.title)
                                                        .font(.caption)
                                                        .fontWeight(.bold)
                                                    Spacer()
                                                    if let similarity = result.similarity {
                                                        Text(String(format: "%.1f%% Match", similarity * 100))
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(.green)
                                                    }
                                                }
                                                Text(result.memory.content)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(6)
                                            .background(Color.blue.opacity(0.05))
                                            .cornerRadius(4)
                                        }
                                    }
                                } else {
                                    Text("No memories selected for context.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.gray.opacity(0.03))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                        } header: {
                            SectionHeader(title: "Context Generation Pipeline")
                        }
                        
                        Divider()
                    }

                    if let rawPrompt = debugInfo.rawPrompt {
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

struct PipelineStepView: View {
    let step: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(step)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.blue)
                    .clipShape(Circle())
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Text(description)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

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
