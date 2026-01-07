import Foundation

/// State of a loaded document in the context
public struct DocumentContext: Identifiable, Sendable, Codable {
    public let id = UUID()
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
        case full
        case excerpt
        case summary
        case metadata
    }
    
    public init(path: String, content: String, viewMode: ViewMode = .full, excerptOffset: Int = 0, excerptLength: Int = 1000, isPinned: Bool = false, lastAccessed: Date = Date()) {
        self.path = path
        self.content = content
        self.fileSize = content.count // Fallback if not provided, though ideally we pass it
        self.viewMode = viewMode
        self.excerptOffset = excerptOffset
        self.excerptLength = excerptLength
        self.isPinned = isPinned
        self.lastAccessed = lastAccessed
    }
    
    /// Get the visible content based on view mode
    public var visibleContent: String {
        switch viewMode {
        case .full:
            return content
        case .summary:
            return summary ?? "[Summary not available]"
        case .excerpt:
            let start = content.index(content.startIndex, offsetBy: excerptOffset, limitedBy: content.endIndex) ?? content.startIndex
            let end = content.index(start, offsetBy: excerptLength, limitedBy: content.endIndex) ?? content.endIndex
            return String(content[start..<end])
        case .metadata:
            return "[Content not loaded. Size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))]"
        }
    }
}
