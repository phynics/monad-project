import MonadShared
import Foundation

extension SemanticSearchResult: Codable {
    enum CodingKeys: String, CodingKey {
        case memory, similarity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.memory = try container.decode(Memory.self, forKey: .memory)
        self.similarity = try container.decodeIfPresent(Double.self, forKey: .similarity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memory, forKey: .memory)
        try container.encodeIfPresent(similarity, forKey: .similarity)
    }
}
