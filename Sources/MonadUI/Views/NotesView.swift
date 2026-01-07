import MonadCore
import SwiftUI

/// View for managing context notes
struct NotesView: View {
    var persistenceManager: PersistenceManager
    @Environment(\.dismiss) var dismiss

    @State private var notes: [Note] = []
    @State private var searchQuery = ""
    @State private var selectedNote: Note?
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var noteToDelete: Note?
    @State private var errorMessage: String?

    var filteredNotes: [Note] {
        guard !searchQuery.isEmpty else { return notes }
        return notes.filter { $0.matches(query: searchQuery) }
    }

    var body: some View {
        NavigationSplitView {
            notesList
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingEditor) {
            if let note = selectedNote {
                NoteEditorView(
                    note: note,
                    persistenceManager: persistenceManager,
                    onSave: { loadNotes() }
                )
            } else {
                NoteEditorView(
                    note: nil,
                    persistenceManager: persistenceManager,
                    onSave: { loadNotes() }
                )
            }
        }
        .confirmationDialog(
            "Delete Note?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: noteToDelete
        ) { note in
            Button("Delete", role: .destructive) {
                deleteNote(note)
            }
        } message: { note in
            Text("Are you sure you want to delete '\(note.name)'? This cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            loadNotes()
        }
    }

    private func loadNotes() {
        Task {
            do {
                let loaded = try await persistenceManager.fetchAllNotes()
                notes = loaded
            } catch {
                errorMessage = "Failed to load notes: \(error.localizedDescription)"
            }
        }
    }

    private func createNewNote() {
        selectedNote = nil
        showingEditor = true
    }

    private func deleteNote(_ note: Note) {
        Task {
            do {
                try await persistenceManager.deleteNote(id: note.id)
                loadNotes()
                if selectedNote?.id == note.id {
                    selectedNote = nil
                }
            } catch {
                errorMessage = "Failed to delete note: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - View Components

    private var notesList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $searchQuery)
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

            // Notes list
            List(selection: $selectedNote) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note)
                        .tag(note)
                        .contextMenu {
                            Button("Edit") {
                                selectedNote = note
                                showingEditor = true
                            }

                            if !note.isReadonly {
                                Divider()
                                Button("Delete", role: .destructive) {
                                    noteToDelete = note
                                    showingDeleteConfirmation = true
                                }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Context Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNewNote) {
                    Label("New Note", systemImage: "plus")
                }
            }
        }
    }

    private var detailView: some View {
        Group {
            if let note = selectedNote {
                NoteDetailView(
                    note: note,
                    onEdit: {
                        showingEditor = true
                    })
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Note Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select a note to view its content")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.name)
                    .font(.headline)

                Spacer()

                if note.alwaysAppend {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if note.isReadonly {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            if !note.description.isEmpty {
                Text(note.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Note Detail View

struct NoteDetailView: View {
    let note: Note
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.name)
                            .font(.title)
                            .fontWeight(.bold)

                        if !note.description.isEmpty {
                            Text(note.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Edit", action: onEdit)
                        .buttonStyle(.bordered)
                }

                // Badges
                HStack(spacing: 8) {
                    if note.alwaysAppend {
                        Label("Always Append", systemImage: "pin.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }

                    if note.isReadonly {
                        Label("Read Only", systemImage: "lock.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.gray)
                            .cornerRadius(4)
                    }
                }

                Divider()

                // Content
                Text(note.content)
                    .textSelection(.enabled)
                    .font(.body)

                Spacer()
            }
            .padding()
        }
    }
}
