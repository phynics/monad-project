import SwiftUI
import MonadCore

public struct ChatSidebarView: View {
    @Bindable var viewModel: ChatViewModel
    
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Active Context")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Pinned Memories Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("PINNED MEMORIES", systemImage: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.bold)
                        
                        let pinnedMemories = viewModel.activeMemories.filter { $0.isPinned }
                        
                        if pinnedMemories.isEmpty {
                            Text("No pinned memories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(pinnedMemories) { am in
                                memoryItem(am)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Documents Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("DOCUMENTS", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.bold)
                        
                        if viewModel.documentManager.documents.isEmpty {
                            Text("No active documents")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(viewModel.documentManager.documents) { doc in
                                documentItem(doc)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(width: 250)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
    
    private func memoryItem(_ am: ActiveMemory) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(am.memory.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(am.memory.content)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button {
                viewModel.toggleMemoryPin(id: am.id)
            } label: {
                Image(systemName: "pin.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func documentItem(_ doc: DocumentContext) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(from: doc.path))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(doc.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    viewModel.documentManager.togglePin(path: doc.path)
                } label: {
                    Image(systemName: doc.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(doc.isPinned ? .blue : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                Button {
                    viewModel.documentManager.unloadDocument(path: doc.path)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
