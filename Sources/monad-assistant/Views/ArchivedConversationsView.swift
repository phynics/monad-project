import SwiftUI

struct ArchivedConversationsView: View {
    var persistenceManager: PersistenceManager
    @Environment(\.dismiss) var dismiss

    @State private var searchQuery: String = ""
    @State private var selectedSession: ConversationSession?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: ConversationSession?
    @State private var errorMessage: String?

    var filteredSessions: [ConversationSession] {
        if searchQuery.isEmpty {
            return persistenceManager.archivedSessions
        } else {
            return persistenceManager.archivedSessions.filter { session in
                session.title.localizedCaseInsensitiveContains(searchQuery)
                    || session.tagArray.contains {
                        $0.localizedCaseInsensitiveContains(searchQuery)
                    }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Archived Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search conversations...", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Content
            if filteredSessions.isEmpty {
                emptyStateView
            } else {
                conversationsList
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("Delete Conversation?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                }
            }
        } message: {
            Text(
                "This will permanently delete '\(sessionToDelete?.title ?? "this conversation")' and all its messages. This action cannot be undone."
            )
        }
        .task {
            await loadArchivedSessions()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: searchQuery.isEmpty ? "archivebox" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(searchQuery.isEmpty ? "No Archived Conversations" : "No Results")
                .font(.headline)
                .foregroundColor(.secondary)

            if searchQuery.isEmpty {
                Text("Archived conversations will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversations List

    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredSessions) { session in
                    ConversationRow(
                        session: session,
                        isSelected: selectedSession?.id == session.id,
                        onSelect: { selectedSession = session },
                        onUnarchive: { unarchiveSession(session) },
                        onDelete: {
                            sessionToDelete = session
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func loadArchivedSessions() async {
        await persistenceManager.loadArchivedSessions()
    }

    private func unarchiveSession(_ session: ConversationSession) {
        Task {
            do {
                var updatedSession = session
                updatedSession.isArchived = false
                updatedSession.updatedAt = Date()
                try await persistenceManager.updateSession(updatedSession)

                // Refresh list
                await loadArchivedSessions()
            } catch {
                errorMessage = "Failed to unarchive: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSession(_ session: ConversationSession) {
        Task {
            do {
                try await persistenceManager.deleteSession(id: session.id)

                // Clear selection if deleted
                if selectedSession?.id == session.id {
                    selectedSession = nil
                }

                // Refresh list
                await loadArchivedSessions()

                sessionToDelete = nil
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
                sessionToDelete = nil
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let session: ConversationSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onUnarchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(session.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !session.tagArray.isEmpty {
                            ForEach(session.tagArray.prefix(3), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onUnarchive) {
                        Label("Unarchive", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Restore this conversation")

                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .help("Delete permanently")
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Preview

#Preview {
    ArchivedConversationsView(
        persistenceManager: PersistenceManager(
            persistence: try! PersistenceService.create()
        )
    )
}
