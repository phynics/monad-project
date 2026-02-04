import XCTest
import GRDB
@testable import MonadCore

final class NotesMigrationUtilityTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        dbQueue = try! DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try! migrator.migrate(dbQueue)
        
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    func testMigrateNotesToFilesystem() async throws {
        // 1. Create a Note in DB
        let noteId = UUID()
        let note = Note(
            id: noteId,
            name: "TestNote",
            description: "A test description",
            content: "Hello from DB",
            isReadonly: false
        )
        try await dbQueue.write { db in
            try note.insert(db)
        }
        
        // 2. Create a Session and its primary Workspace
        let sessionId = UUID()
        let sessionWorkspaceURL = tempURL.appendingPathComponent("sessions/\(sessionId.uuidString)")
        try FileManager.default.createDirectory(at: sessionWorkspaceURL, withIntermediateDirectories: true)
        
        let workspace = Workspace(
            uri: .serverSession(sessionId),
            hostType: .server,
            rootPath: sessionWorkspaceURL.path
        )
        
        let session = ConversationSession(id: sessionId, title: "Test Session", primaryWorkspaceId: workspace.id)
        
        try await dbQueue.write { db in
            try workspace.insert(db)
            try session.insert(db)
        }
        
        // 3. Run migration
        let utility = NotesMigrationUtility(dbQueue: dbQueue)
        let count = try await utility.migrateAllNotes()
        
        XCTAssertGreaterThanOrEqual(count, 1)
        
        // 4. Verify file existence and content
        let noteFileURL = sessionWorkspaceURL.appendingPathComponent("Notes/TestNote.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteFileURL.path))
        
        let content = try String(contentsOf: noteFileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("_Description: A test description_"))
        XCTAssertTrue(content.contains("Hello from DB"))
    }
}
