import XCTest
@testable import MonadCore

@MainActor
final class DocumentManagerTests: XCTestCase {
    
    var manager: DocumentManager!
    
    override func setUp() {
        manager = DocumentManager()
    }
    
    func testLoadAndUnloadDocument() {
        let path = "/tmp/test.txt"
        let content = "Hello World"
        
        // Load
        manager.loadDocument(path: path, content: content)
        XCTAssertEqual(manager.documents.count, 1)
        XCTAssertEqual(manager.documents.first?.path, path)
        XCTAssertEqual(manager.documents.first?.content, content)
        
        // Reload (replace)
        manager.loadDocument(path: path, content: "New Content")
        XCTAssertEqual(manager.documents.count, 1)
        XCTAssertEqual(manager.documents.first?.content, "New Content")
        
        // Unload
        manager.unloadDocument(path: path)
        XCTAssertTrue(manager.documents.isEmpty)
    }
    
    func testTogglePin() {
        let path = "/tmp/doc1.txt"
        manager.loadDocument(path: path, content: "Content")
        XCTAssertFalse(manager.getDocument(path: path)!.isPinned)
        
        manager.togglePin(path: path)
        XCTAssertTrue(manager.getDocument(path: path)!.isPinned)
        
        manager.togglePin(path: path)
        XCTAssertFalse(manager.getDocument(path: path)!.isPinned)
    }
    
    func testGetEffectiveDocuments() {
        // Create 3 documents
        manager.loadDocument(path: "/doc1", content: "1") // Unpinned, Old
        manager.loadDocument(path: "/doc2", content: "2") // Unpinned, New
        manager.loadDocument(path: "/doc3", content: "3") // Pinned
        
        // Modify lastAccessed to ensure ordering
        var doc1 = manager.getDocument(path: "/doc1")!
        doc1.lastAccessed = Date().addingTimeInterval(-1000)
        manager.updateDocument(doc1)
        
        var doc2 = manager.getDocument(path: "/doc2")!
        doc2.lastAccessed = Date()
        manager.updateDocument(doc2)
        
        manager.togglePin(path: "/doc3")
        
        // Limit 1 for unpinned
        let effective = manager.getEffectiveDocuments(limit: 1)
        
        // Should contain Pinned (doc3) + 1 Most Recent Unpinned (doc2)
        XCTAssertEqual(effective.count, 2)
        XCTAssertEqual(effective[0].path, "/doc3") // Pinned first
        XCTAssertEqual(effective[1].path, "/doc2") // Recent next
        
        // Doc1 should be excluded
        XCTAssertFalse(effective.contains(where: { $0.path == "/doc1" }))
    }
    
    func testDocumentContextVisibleContent() {
        let content = "0123456789"
        let doc = DocumentContext(path: "/test", content: content, viewMode: .raw)
        
        // Raw Mode
        XCTAssertTrue(doc.visibleContent.contains(content))
        XCTAssertTrue(doc.visibleContent.contains("--- RAW CONTENT ---"))
        
        // Metadata Mode
        var metaDoc = doc
        metaDoc.viewMode = .metadata
        XCTAssertFalse(metaDoc.visibleContent.contains("--- RAW CONTENT ---"))
        XCTAssertTrue(metaDoc.visibleContent.contains("SIZE:"))
        
        // Excerpt Mode
        var excerptDoc = doc
        excerptDoc.viewMode = .excerpt
        excerptDoc.excerptOffset = 2
        excerptDoc.excerptLength = 4
        XCTAssertTrue(excerptDoc.visibleContent.contains("--- EXCERPT"))
        XCTAssertTrue(excerptDoc.visibleContent.contains("2345"))
        XCTAssertFalse(excerptDoc.visibleContent.contains("01")) // Before offset
        XCTAssertFalse(excerptDoc.visibleContent.contains("6789")) // After length
        
        // Excerpt Out of Bounds (Safety Check)
        excerptDoc.excerptOffset = 50
        XCTAssertNoThrow(excerptDoc.visibleContent)
        // Should effectively be empty string for content part, but contain headers
        
        // Summary Mode
        var summaryDoc = doc
        summaryDoc.viewMode = .summary
        summaryDoc.summary = "A nice summary"
        XCTAssertTrue(summaryDoc.visibleContent.contains("--- MANUAL SUMMARY ---"))
        XCTAssertTrue(summaryDoc.visibleContent.contains("A nice summary"))
    }
}
