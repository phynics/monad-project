import MonadCore
import SwiftUI

struct MessageDebugPromptContextView: View {
    let debugInfo: MessageDebugInfo
    
    @State private var selectedTab = 0
    private let sectionOrder = [
        "system", "context_notes", "documents", "memories", "database_directory", "tools", "chat_history", "user_query"
    ]
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("View Mode", selection: $selectedTab) {
                    Text("Structured").tag(0)
                    Text("Raw").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                
                if selectedTab == 0 {
                    // Structured View
                    if let structured = debugInfo.structuredContext {
                        ForEach(sectionOrder, id: \.self) { sectionId in
                            if let content = structured[sectionId] {
                                ContextSectionView(title: sectionTitle(for: sectionId), content: content)
                            }
                        }
                        
                        ForEach(structured.keys.sorted().filter { !sectionOrder.contains($0) }, id: \.self) { sectionId in
                            if let content = structured[sectionId] {
                                ContextSectionView(title: sectionId.capitalized, content: content)
                            }
                        }
                    } else {
                        Text("Structured context not available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Raw View
                    if let rawPrompt = debugInfo.rawPrompt {
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
                    }
                }
            }
        } header: {
            SectionHeader(title: "Prompt Context")
        }
    }
    
    private func sectionTitle(for id: String) -> String {
        switch id {
        case "system": return "System Instructions"
        case "context_notes": return "Context Notes"
        case "documents": return "Active Documents"
        case "memories": return "Recalled Memories"
        case "database_directory": return "Database Directory"
        case "tools": return "Available Tools"
        case "chat_history": return "Chat History"
        case "user_query": return "User Query"
        default: return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct ContextSectionView: View {
    let title: String
    let content: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Copy") {
                            #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(content, forType: .string)
                            #else
                                UIPasteboard.general.string = content
                            #endif
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}