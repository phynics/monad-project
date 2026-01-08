import SwiftUI
import MonadCore

public struct ChatSidebarView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var selectedDocument: DocumentContext?
    
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Active Context")
                    .font(.headline)
                Spacer()
                
                if !viewModel.activeMemories.isEmpty || !viewModel.documentManager.documents.isEmpty {
                    Button("Clear All") {
                        viewModel.activeMemories.removeAll()
                        for doc in viewModel.documentManager.documents {
                            viewModel.documentManager.unloadDocument(path: doc.path)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Memories Section
                    VStack(alignment: .leading, spacing: 12) {
                        let pinnedMemories = viewModel.activeMemories.filter { $0.isPinned }
                        let unpinnedMemories = viewModel.activeMemories.filter { !$0.isPinned }
                        
                        if !pinnedMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("PINNED MEMORIES", systemImage: "pin.fill", color: .blue)
                                
                                ForEach(pinnedMemories) { am in
                                    memoryItem(am)
                                }
                            }
                        }
                        
                        if !unpinnedMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("INSERTED MEMORIES", systemImage: "brain.head.profile", color: .secondary)
                                
                                ForEach(unpinnedMemories.sorted(by: { $0.lastAccessed > $1.lastAccessed }).prefix(5)) { am in
                                    memoryItem(am)
                                }
                            }
                        }
                        
                        if pinnedMemories.isEmpty && unpinnedMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("MEMORIES", systemImage: "brain.head.profile", color: .secondary)
                                emptyState("No memories active")
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Documents Section
                    VStack(alignment: .leading, spacing: 12) {
                        let pinnedDocs = viewModel.documentManager.documents.filter { $0.isPinned }
                        let unpinnedDocs = viewModel.documentManager.documents.filter { !$0.isPinned }
                        
                        if !pinnedDocs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("PINNED DOCUMENTS", systemImage: "pin.fill", color: .blue)
                                
                                ForEach(pinnedDocs) { doc in
                                    documentItem(doc)
                                }
                            }
                        }
                        
                        if !unpinnedDocs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("LOADED DOCUMENTS", systemImage: "doc.text", color: .secondary)
                                
                                ForEach(unpinnedDocs) { doc in
                                    documentItem(doc)
                                }
                            }
                        }
                        
                        if pinnedDocs.isEmpty && unpinnedDocs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("DOCUMENTS", systemImage: "doc.text", color: .secondary)
                                emptyState("No documents loaded")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 280)
        .background(Color(.windowBackgroundColor))
        .sheet(item: $selectedDocument) { doc in
            DocumentContextDetailView(document: doc)
        }
    }
    
    private func sectionHeader(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundColor(color)
            .fontWeight(.bold)
    }
    
    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .italic()
            .padding(.leading, 4)
    }
    
    private func memoryItem(_ am: ActiveMemory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(am.memory.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Button {
                        viewModel.toggleMemoryPin(id: am.id)
                    } label: {
                        Image(systemName: am.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(am.isPinned ? .blue : .secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        viewModel.removeActiveMemory(id: am.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(am.memory.content)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(am.isPinned ? Color.blue.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(am.isPinned ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    
    private func documentItem(_ doc: DocumentContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    selectedDocument = doc
                } label: {
                    Text(fileName(from: doc.path))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Button {
                        viewModel.documentManager.togglePin(path: doc.path)
                    } label: {
                        Image(systemName: doc.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(doc.isPinned ? .blue : .secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        viewModel.documentManager.unloadDocument(path: doc.path)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                selectedDocument = doc
            } label: {
                Text(doc.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(doc.isPinned ? Color.blue.opacity(0.05) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(doc.isPinned ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    
    private func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
