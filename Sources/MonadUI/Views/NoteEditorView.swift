import MonadCore
import SwiftUI

/// Editor for creating and updating notes
struct NoteEditorView: View {
    let note: Note?
    let persistenceManager: PersistenceManager
    let onSave: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var content: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    
    init(note: Note?, persistenceManager: PersistenceManager, onSave: @escaping () -> Void) {
        self.note = note
        self.persistenceManager = persistenceManager
        self.onSave = onSave
        
        // Initialize state from note or defaults
        _name = State(initialValue: note?.name ?? "")
        _description = State(initialValue: note?.description ?? "")
        _content = State(initialValue: note?.content ?? "")
    }
    
    var isValid: Bool {
        !name.isEmpty && !content.isEmpty
    }
    
    var isReadonly: Bool {
        note?.isReadonly ?? false
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Description (optional)", text: $description)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Basic Info")
                } footer: {
                    if isReadonly {
                        Text("System Note: Editing is allowed for both you and the LLM to support recursive growth.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $content)
                            .font(.body)
                            .frame(minHeight: 200)
                    }
                } header: {
                    Text("Note Content")
                } footer: {
                    Text("This content will be injected into the LLM context.")
                        .font(.caption)
                }
                
                if let note = note {
                    Section {
                        LabeledContent("Created") {
                            Text(note.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        LabeledContent("Updated") {
                            Text(note.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Metadata")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func saveNote() {
        guard isValid else { return }
        
        isSaving = true
        
        Task {
            do {
                let noteToSave: Note
                if let existing = note {
                    // Update existing note
                    noteToSave = Note(
                        id: existing.id,
                        name: name,
                        description: description,
                        content: content,
                        isReadonly: existing.isReadonly,
                        createdAt: existing.createdAt,
                        updatedAt: Date()
                    )
                } else {
                    // Create new note
                    noteToSave = Note(
                        name: name,
                        description: description,
                        content: content,
                        isReadonly: false
                    )
                }
                
                try await persistenceManager.saveNote(noteToSave)
                
                isSaving = false
                onSave()
                dismiss()
            } catch {
                errorMessage = "Failed to save note: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}
