import SwiftUI
import MonadCore

public struct SubagentContextView: View {
    public let context: SubagentContext
    @Environment(\.dismiss) private var dismiss
    
    public init(context: SubagentContext) {
        self.context = context
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(context.prompt)
                        .font(.body)
                } header: {
                    Label("Subagent Prompt", systemImage: "text.justify.left")
                        .foregroundColor(.purple)
                }
                
                Section {
                    if context.documents.isEmpty {
                        Text("No documents")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(context.documents, id: \.self) { path in
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.purple)
                                Text(path)
                                    .monospaced()
                            }
                        }
                    }
                } header: {
                    Label("Context Documents", systemImage: "folder.fill")
                        .foregroundColor(.purple)
                }
                
                if let raw = context.rawResponse {
                    Section {
                        Text(raw)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        Label("Raw Response", systemImage: "terminal.fill")
                            .foregroundColor(.purple)
                    }
                }
            }
            .navigationTitle("Subagent Details")
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
