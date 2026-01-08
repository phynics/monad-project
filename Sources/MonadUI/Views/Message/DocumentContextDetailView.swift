import SwiftUI
import MonadCore

public struct DocumentContextDetailView: View {
    public let document: DocumentContext
    @Environment(\.dismiss) private var dismiss
    
    public init(document: DocumentContext) {
        self.document = document
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Path") {
                    Text(document.path)
                        .font(.body)
                        .monospaced()
                }
                
                Section("Status") {
                    LabeledContent("View Mode", value: document.viewMode.rawValue.capitalized)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(document.fileSize), countStyle: .file))
                    if document.viewMode == .excerpt {
                        LabeledContent("Offset", value: "\(document.excerptOffset)")
                        LabeledContent("Length", value: "\(document.excerptLength)")
                    }
                    LabeledContent("Pinned", value: document.isPinned ? "Yes" : "No")
                }
                
                if let summary = document.summary {
                    Section("Summary") {
                        Text(summary)
                            .font(.body)
                    }
                }
                
                Section("Content (\(document.viewMode.rawValue.capitalized))") {
                    Text(document.visibleContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Document Context")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}
