import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore
import NIOCore

@Suite struct NoteControllerTests {
    
    @Test("Test Notes CRUD")
    func testNotesCRUD() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        
        let router = Router()
        let controller = NoteController<BasicRequestContext>(sessionManager: sessionManager)
        controller.addRoutes(to: router.group("/notes"))
        
        let app = Application(router: router)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        try await app.test(.router) { client in
            // 1. List (Empty)
            try await client.execute(uri: "/notes", method: .get) { response in
                #expect(response.status == .ok)
                let notes = try decoder.decode([Note].self, from: response.body)
                #expect(notes.isEmpty)
            }
            
            // 2. Create
            let createReq = CreateNoteRequest(name: "Test Note", content: "Test Content", description: "Test Desc", tags: ["test"])
            let createBuffer = ByteBuffer(bytes: try JSONEncoder().encode(createReq))
            
            try await client.execute(uri: "/notes", method: .post, body: createBuffer) { response in
                #expect(response.status == .created)
                let note = try decoder.decode(Note.self, from: response.body)
                #expect(note.name == "Test Note")
                #expect(note.tagArray == ["test"])
            }
            
            // 3. List (1 item)
            try await client.execute(uri: "/notes", method: .get) { response in
                #expect(response.status == .ok)
                let notes = try decoder.decode([Note].self, from: response.body)
                #expect(notes.count == 1)
                #expect(notes[0].name == "Test Note")
            }
            
            let listResponse = try await client.execute(uri: "/notes", method: .get) { $0 }
            let noteId = (try decoder.decode([Note].self, from: listResponse.body))[0].id
            
            // 4. Delete
            try await client.execute(uri: "/notes/\(noteId)", method: .delete) { response in
                #expect(response.status == .noContent)
            }
            
            // 5. List (Empty)
            try await client.execute(uri: "/notes", method: .get) { response in
                let notes = try decoder.decode([Note].self, from: response.body)
                #expect(notes.isEmpty)
            }
        }
    }
}

public struct CreateNoteRequest: Codable {
    public let name: String
    public let content: String
    public let description: String?
    public let tags: [String]?
}
