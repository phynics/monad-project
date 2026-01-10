import MonadCore
import SwiftUI

public struct ChatSidebarView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var selectedDocument: DocumentContext?

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    memoriesSection
                    Divider()
                    documentsSection
                    Divider()
                    jobQueueSection
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

    private var header: some View {
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
    }

    @ViewBuilder
    private var memoriesSection: some View {
        let pinnedMemories = viewModel.activeMemories.filter { $0.isPinned }
        let unpinnedMemories = viewModel.activeMemories.filter { !$0.isPinned }

        VStack(alignment: .leading, spacing: 12) {
            if !pinnedMemories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("PINNED MEMORIES", systemImage: "pin.fill", color: .blue)
                    ForEach(pinnedMemories) { am in
                        SidebarMemoryItem(
                            am: am,
                            onTogglePin: { viewModel.toggleMemoryPin(id: am.id) },
                            onRemove: { viewModel.removeActiveMemory(id: am.id) }
                        )
                    }
                }
            }

            if !unpinnedMemories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("INSERTED MEMORIES", systemImage: "brain.head.profile", color: .secondary)
                    ForEach(unpinnedMemories.sorted(by: { $0.lastAccessed > $1.lastAccessed }).prefix(5)) { am in
                        SidebarMemoryItem(
                            am: am,
                            onTogglePin: { viewModel.toggleMemoryPin(id: am.id) },
                            onRemove: { viewModel.removeActiveMemory(id: am.id) }
                        )
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
    }

    @ViewBuilder
    private var documentsSection: some View {
        let pinnedDocs = viewModel.documentManager.documents.filter { $0.isPinned }
        let unpinnedDocs = viewModel.documentManager.documents.filter { !$0.isPinned }

        VStack(alignment: .leading, spacing: 12) {
            if !pinnedDocs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("PINNED DOCUMENTS", systemImage: "pin.fill", color: .blue)
                    ForEach(pinnedDocs) { doc in
                        SidebarDocumentItem(
                            doc: doc,
                            onSelect: { selectedDocument = doc },
                            onTogglePin: { viewModel.documentManager.togglePin(path: doc.path) },
                            onUnload: { viewModel.documentManager.unloadDocument(path: doc.path) }
                        )
                    }
                }
            }

            if !unpinnedDocs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("LOADED DOCUMENTS", systemImage: "doc.text", color: .secondary)
                    ForEach(unpinnedDocs) { doc in
                        SidebarDocumentItem(
                            doc: doc,
                            onSelect: { selectedDocument = doc },
                            onTogglePin: { viewModel.documentManager.togglePin(path: doc.path) },
                            onUnload: { viewModel.documentManager.unloadDocument(path: doc.path) }
                        )
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

    @ViewBuilder
    private var jobQueueSection: some View {
        let jobs = viewModel.jobQueueContext.listJobs()
        let pendingJobs = jobs.filter { $0.status == .pending }
        let inProgressJobs = jobs.filter { $0.status == .inProgress }

        VStack(alignment: .leading, spacing: 12) {
            if !inProgressJobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("IN PROGRESS", systemImage: "arrow.triangle.2.circlepath", color: .orange)
                    ForEach(inProgressJobs) { job in
                        SidebarJobItem(job: job)
                    }
                }
            }

            if !pendingJobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("PENDING JOBS", systemImage: "tray.full", color: .secondary)
                    ForEach(pendingJobs) { job in
                        SidebarJobItem(job: job)
                    }
                }
            }

            if pendingJobs.isEmpty && inProgressJobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("JOB QUEUE", systemImage: "tray", color: .secondary)
                    emptyState("No jobs queued")
                }
            }
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
}