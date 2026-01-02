import Foundation

/// Helper for Codable 'Any' types, often used in JSON-RPC and dynamic tool arguments.
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            value = x
        } else if let x = try? container.decode(Double.self) {
            value = x
        } else if let x = try? container.decode(Bool.self) {
            value = x
        } else if let x = try? container.decode(String.self) {
            value = x
        } else if let x = try? container.decode([AnyCodable].self) {
            value = x.map { $0.value }
        } else if let x = try? container.decode([String: AnyCodable].self) {
            value = x.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? Int {
            try container.encode(x)
        } else if let x = value as? Double {
            try container.encode(x)
        } else if let x = value as? Bool {
            try container.encode(x)
        } else if let x = value as? String {
            try container.encode(x)
        } else if let x = value as? [Any] {
            try container.encode(x.map(AnyCodable.init))
        } else if let x = value as? [String: Any] {
            try container.encode(x.mapValues(AnyCodable.init))
        } else if let x = value as? [AnyCodable] {
            try container.encode(x)
        } else if let x = value as? [String: AnyCodable] {
            try container.encode(x)
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(
                value, .init(codingPath: encoder.codingPath, debugDescription: "Invalid value"))
        }
    }
}
