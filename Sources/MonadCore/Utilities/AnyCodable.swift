import Foundation

/// Helper for Codable 'Any' types, often used in JSON-RPC and dynamic tool arguments.
public struct AnyCodable: Codable, @unchecked Sendable, Equatable, CustomStringConvertible {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public var description: String {
        "\(value)"
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as Bool, let r as Bool): return l == r
        case (let l as String, let r as String): return l == r
        case (let l as [AnyCodable], let r as [AnyCodable]): return l == r
        case (let l as [String: AnyCodable], let r as [String: AnyCodable]): return l == r
        case (let l as [Any], let r as [Any]):
            // Best effort for [Any] if elements are equatable standard types
            guard l.count == r.count else { return false }
            // Recursively wrap in AnyCodable to check equality
            return zip(l, r).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case (let l as [String: Any], let r as [String: Any]):
             guard l.count == r.count else { return false }
             return l.keys.allSatisfy { key in
                 guard let lv = l[key], let rv = r[key] else { return false }
                 return AnyCodable(lv) == AnyCodable(rv)
             }
        case (is NSNull, is NSNull): return true
        default: return false
        }
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
        
        func wrap(_ val: Any) -> AnyCodable {
            if let ac = val as? AnyCodable { return ac }
            return AnyCodable(val)
        }

        if let ac = value as? AnyCodable {
            try ac.encode(to: encoder)
        } else if let x = value as? Int {
            try container.encode(x)
        } else if let x = value as? Double {
            try container.encode(x)
        } else if let x = value as? Bool {
            try container.encode(x)
        } else if let x = value as? String {
            try container.encode(x)
        } else if let x = value as? [AnyCodable] {
            try container.encode(x)
        } else if let x = value as? [String: AnyCodable] {
            try container.encode(x)
        } else if let x = value as? [Any] {
            try container.encode(x.map(wrap))
        } else if let x = value as? [String: Any] {
            try container.encode(x.mapValues(wrap))
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(
                value, .init(codingPath: encoder.codingPath, debugDescription: "Invalid value"))
        }
    }
}
