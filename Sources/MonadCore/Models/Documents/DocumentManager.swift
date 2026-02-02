import Foundation

/// Manages loaded documents for the session
public actor DocumentManager: Sendable {
    public private(set) var documents: [DocumentContext] = []
    
    public init() {}
    
    public func loadDocument(path: String, content: String) {
        // Standardize path if it's a real file path
        let targetPath = standardize(path)
        
        // Remove existing if present (reload)
        unloadDocument(path: targetPath)
        
        let doc = DocumentContext(path: targetPath, content: content)
        documents.append(doc)
    }
    
    public func unloadDocument(path: String) {
        let targetPath = standardize(path)
        documents.removeAll { $0.path == targetPath }
    }
    
    public func updateDocument(_ document: DocumentContext) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        }
    }
    
    public func getDocument(path: String) -> DocumentContext? {
        let targetPath = standardize(path)
        return documents.first { $0.path == targetPath }
    }
    
    public func togglePin(path: String) {
        let targetPath = standardize(path)
        guard let index = documents.firstIndex(where: { $0.path == targetPath }) else { return }
        var doc = documents[index]
        doc.isPinned.toggle()
        documents[index] = doc
    }
    
    private func standardize(_ path: String) -> String {
        if path.starts(with: "archived://") {
            return path
        }
        return URL(fileURLWithPath: path).standardized.path
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
    
    public func getAllDocuments() -> [DocumentContext] {
        return documents
    }
}