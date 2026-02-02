import MonadCore
import SwiftUI
import OSLog

public struct MemoriesView: View {
    let persistenceManager: PersistenceManager
    @State private var memories: [Memory] = []
    @State private var searchText = ""
    @State private var selectedMemory: Memory?
    @State private var showingDeleteConfirmation = false
    @State private var memoryToDelete: Memory?
    
    @Environment(\.dismiss) private var dismiss

    public init(persistenceManager: PersistenceManager) {
        self.persistenceManager = persistenceManager
    }

    public var body: some View {
        NavigationStack {
            List {
                if memories.isEmpty {
                    ContentUnavailableView(
                        "No Memories",
                        systemImage: "brain.head.profile",
                        description: Text("Created memories will appear here.")
                    )
                } else {
                    ForEach(filteredMemories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.title)
                                .font(.headline)
                            
                            if !memory.content.isEmpty {
                                Text(memory.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            
                            if !memory.tagArray.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(memory.tagArray, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundStyle(.blue)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            
                            Text(memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMemory = memory
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                memoryToDelete = memory
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteMemories)
                }
            }
            .searchable(text: $searchText, prompt: "Search memories...")
            .navigationTitle("Memories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
            .confirmationDialog(
                "Delete Memory?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let memory = memoryToDelete {
                        deleteMemory(memory)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let memory = memoryToDelete {
                    Text("Are you sure you want to delete '\(memory.title)'? This cannot be undone.")
                }
            }
            .onAppear {
                loadMemories()
            }
        }
    }
    
    private var filteredMemories: [Memory] {
        if searchText.isEmpty {
            return memories
        }
        return memories.filter { memory in
            memory.title.localizedCaseInsensitiveContains(searchText) ||
            memory.content.localizedCaseInsensitiveContains(searchText) ||
            memory.tagArray.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private func loadMemories() {
        Task {
            do {
                memories = try await persistenceManager.fetchAllMemories()
            } catch {
                Logger.database.error("Failed to fetch memories: \(error)")
            }
        }
    }
    
    private func deleteMemories(at offsets: IndexSet) {
        let memoriesToDelete = offsets.map { filteredMemories[$0] }
        for memory in memoriesToDelete {
            deleteMemory(memory)
        }
    }
    
    private func deleteMemory(_ memory: Memory) {
        Task {
            do {
                try await persistenceManager.deleteMemory(id: memory.id)
                await MainActor.run {
                    if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                        memories.remove(at: index)
                    }
                }
            } catch {
                Logger.database.error("Failed to delete memory: \(error)")
            }
        }
    }
}

struct MemoryDetailView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !memory.tagArray.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(memory.tagArray, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.subheadline)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    Text(memory.content)
                        .font(.body)
                        .textSelection(.enabled)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Metadata")
                            .font(.headline)
                        
                        LabeledContent("Created", value: memory.createdAt.formatted(date: .long, time: .shortened))
                        LabeledContent("Updated", value: memory.updatedAt.formatted(date: .long, time: .shortened))
                        LabeledContent("ID", value: memory.id.uuidString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(memory.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
