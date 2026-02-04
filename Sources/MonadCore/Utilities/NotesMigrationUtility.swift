import Foundation
import GRDB
import Logging

/// Utility to migrate database-backed Notes to session-specific filesystem storage
public struct NotesMigrationUtility {
    private let dbQueue: DatabaseQueue
    private let logger = Logger(label: "com.monad.NotesMigrationUtility")
    
    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    /// Migrate all notes from the database to the primary workspace of every active session
    /// - Returns: Total number of files created
    public func migrateAllNotes() async throws -> Int {
        let (notes, sessions, workspaces) = try await dbQueue.read { db -> ([Note], [ConversationSession], [Workspace]) in
            let notes = try Note.fetchAll(db)
            let sessions = try ConversationSession.fetchAll(db)
            let workspaces = try Workspace.fetchAll(db)
            return (notes, sessions, workspaces)
        }
        
        guard !notes.isEmpty else {
            logger.info("No notes found in database to migrate.")
            return 0
        }
        
        let workspaceMap = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        var filesCreated = 0
        
        for session in sessions {
            guard let primaryWorkspaceId = session.primaryWorkspaceId,
                  let workspace = workspaceMap[primaryWorkspaceId],
                  let rootPath = workspace.rootPath else {
                continue
            }
            
            let notesDir = URL(fileURLWithPath: rootPath).appendingPathComponent("Notes", isDirectory: true)
            
            do {
                try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
                
                for note in notes {
                    let sanitizedName = sanitizeFilename(note.name)
                    let fileURL = notesDir.appendingPathComponent("\(sanitizedName).md")
                    
                    let content = """
                    _Description: \(note.description)_
                    
                    \(note.content)
                    """
                    
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    filesCreated += 1
                    logger.debug("Migrated note '\(note.name)' to \(fileURL.path)")
                }
            } catch {
                logger.error("Failed to migrate notes for session \(session.id): \(error.localizedDescription)")
            }
        }
        
        logger.info("Migration complete. Created \(filesCreated) note files across \(sessions.count) sessions.")
        return filesCreated
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
