import Foundation

/// State of a loaded document in the context
public struct DocumentContext: Identifiable, Sendable, Codable, Equatable {
    public var id = UUID()
    public let path: String
    public let content: String
    public let fileSize: Int
    public var summary: String?
    public var viewMode: ViewMode
    public var excerptOffset: Int
    public var excerptLength: Int
    public var isPinned: Bool
    public var lastAccessed: Date

    public enum ViewMode: String, Codable, Sendable {
        case raw
        case excerpt
        case summary
        case metadata
    }
    
    public init(path: String, content: String, viewMode: ViewMode = .metadata, excerptOffset: Int = 0, excerptLength: Int = 1000, isPinned: Bool = false, lastAccessed: Date = Date()) {
        self.path = path
        self.content = content
        self.fileSize = content.count
        self.viewMode = viewMode
        self.excerptOffset = excerptOffset
        self.excerptLength = excerptLength
        self.isPinned = isPinned
        self.lastAccessed = lastAccessed
    }
    
    /// Get the visible content based on view mode
    public var visibleContent: String {
        let metadataStr = """
        PATH: \(path)
        SIZE: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        TYPE: \(path.split(separator: ".").last?.uppercased() ?? "UNKNOWN")
        MODE: \(viewMode.rawValue)
        """

        switch viewMode {
        case .raw:
            return """
            \(metadataStr)
            --- RAW CONTENT ---
            \(content)
            """
        case .summary:
            return """
            \(metadataStr)
            --- MANUAL SUMMARY ---
            \(summary ?? "[No manual summary provided]")
            """
        case .excerpt:
            let start = content.index(content.startIndex, offsetBy: excerptOffset, limitedBy: content.endIndex) ?? content.startIndex
            let end = content.index(start, offsetBy: excerptLength, limitedBy: content.endIndex) ?? content.endIndex
            let excerpt = String(content[start..<end])
            return """
            \(metadataStr)
            --- EXCERPT (Offset: \(excerptOffset), Length: \(excerptLength)) ---
            \(excerpt)
            """
        case .metadata:
            return metadataStr
        }
    }
}
