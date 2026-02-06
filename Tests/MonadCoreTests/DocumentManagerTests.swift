import XCTest
import MonadCore

final class DocumentManagerTests: XCTestCase {

    var manager: DocumentManager!

    override func setUp() {
        manager = DocumentManager()
    }

    func testLoadAndUnloadDocument() async {
        let path = "/tmp/test.swift"
        let content = "print('hello')"

        // Load
        await manager.loadDocument(path: path, content: content)
        let docs = await manager.documents
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs.first?.path, path)
        XCTAssertEqual(docs.first?.content, content)

        // Reload (replace)
        await manager.loadDocument(path: path, content: "New Content")
        let docs2 = await manager.documents
        XCTAssertEqual(docs2.count, 1)
        XCTAssertEqual(docs2.first?.content, "New Content")

        // Unload
        await manager.unloadDocument(path: path)
        let docs3 = await manager.documents
        XCTAssertTrue(docs3.isEmpty)
    }

    func testTogglePin() async {
        let path = "/tmp/doc1.txt"
        await manager.loadDocument(path: path, content: "Content")
        let doc = await manager.getDocument(path: path)
        XCTAssertFalse(doc!.isPinned)

        await manager.togglePin(path: path)
        let doc2 = await manager.getDocument(path: path)
        XCTAssertTrue(doc2!.isPinned)

        await manager.togglePin(path: path)
        let doc3 = await manager.getDocument(path: path)
        XCTAssertFalse(doc3!.isPinned)
    }

    func testGetEffectiveDocuments() async {
        // Create 3 documents
        await manager.loadDocument(path: "/doc1", content: "1") // Unpinned, Old
        await manager.loadDocument(path: "/doc2", content: "2") // Unpinned, New
        await manager.loadDocument(path: "/doc3", content: "3") // Pinned

        // Modify lastAccessed to ensure ordering
        var doc1 = await manager.getDocument(path: "/doc1")!
        doc1.lastAccessed = Date().addingTimeInterval(-1000)
        await manager.updateDocument(doc1)

        var doc2 = await manager.getDocument(path: "/doc2")!
        doc2.lastAccessed = Date()
        await manager.updateDocument(doc2)

        await manager.togglePin(path: "/doc3")

        // Limit 1 for unpinned
        let effective = await manager.getEffectiveDocuments(limit: 1)

        // Should contain Pinned (doc3) + 1 Most Recent Unpinned (doc2)
        XCTAssertEqual(effective.count, 2)
        XCTAssertEqual(effective[0].path, "/doc3")
        XCTAssertEqual(effective[1].path, "/doc2")
    }
}
