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
}
