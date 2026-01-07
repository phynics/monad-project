import Foundation
import Observation

/// Manages loaded documents for the session
@MainActor
@Observable
public final class DocumentManager: Sendable {
    public var documents: [DocumentContext] = []
    
    public init() {}
    
    public func loadDocument(path: String, content: String) {
        // Remove existing if present (reload)
        unloadDocument(path: path)
        
        let doc = DocumentContext(path: path, content: content)
        documents.append(doc)
    }
    
    public func unloadDocument(path: String) {
        documents.removeAll { $0.path == path }
    }
    
    public func updateDocument(_ document: DocumentContext) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        }
    }
    
    public func getDocument(path: String) -> DocumentContext? {
        documents.first { $0.path == path }
    }
    
    public func togglePin(path: String) {
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return }
        var doc = documents[index]
        doc.isPinned.toggle()
        documents[index] = doc
    }
    
    public func touchDocument(path: String) {
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return }
        var doc = documents[index]
        doc.lastAccessed = Date()
        documents[index] = doc
    }
    
    /// Get effective list of documents for context injection (Pinned + Recent N)
    public func getEffectiveDocuments(limit: Int) -> [DocumentContext] {
        let pinned = documents.filter { $0.isPinned }
        let unpinned = documents.filter { !$0.isPinned }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(limit)
        
        // Combine and dedup (though filtering ensures disjoint sets)
        // Order: Pinned first, then recent
        return pinned + Array(unpinned)
    }
}
