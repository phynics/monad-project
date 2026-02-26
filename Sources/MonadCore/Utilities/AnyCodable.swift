import Foundation

/// A wrapper for Any that is Codable
public enum AnyCodable: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null

    public var value: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .dictionary(let d): return d.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        case .null: return NSNull()
        }
    }

    public var description: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .boolean(let b): return String(b)
        case .dictionary(let d): return String(describing: d)
        case .array(let a): return String(describing: a)
        case .null: return "null"
        }
    }

    public func toAny() -> Any { value }

    public var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var asDictionary: [String: AnyCodable]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }

    public var asArray: [AnyCodable]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public init(_ value: Any?) {
        if let ac = value as? AnyCodable {
            self = ac
            return
        }
        if let value = value as? String { self = .string(value) }
        else if let value = value as? Double { self = .number(value) }
        else if let value = value as? Int { self = .number(Double(value)) }
        else if let value = value as? Bool { self = .boolean(value) }
        else if let value = value as? [String: Any] { self = .dictionary(value.mapValues { AnyCodable($0) }) }
        else if let value = value as? [Any] { self = .array(value.map { AnyCodable($0) }) }
        else { self = .null }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode([String: AnyCodable].self) { self = .dictionary(value) }
        else if let value = try? container.decode([AnyCodable].self) { self = .array(value) }
        else { self = .null }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - JSON Utilities

public func toJsonString(_ dict: [String: AnyCodable]) throws -> String {
    let anyDict = dict.mapValues { $0.value }
    let data = try JSONSerialization.data(withJSONObject: anyDict, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

extension Dictionary where Key == String, Value == AnyCodable {
    public func toJsonString() throws -> String {
        return try MonadCore.toJsonString(self)
    }
}
