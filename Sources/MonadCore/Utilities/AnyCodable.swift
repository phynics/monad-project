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
        case .string(let str): return str
        case .number(let num): return num
        case .boolean(let bool): return bool
        case .dictionary(let dict): return dict.mapValues { $0.value }
        case .array(let arr): return arr.map { $0.value }
        case .null: return NSNull()
        }
    }

    public var description: String {
        switch self {
        case .string(let str): return str
        case .number(let num): return String(num)
        case .boolean(let bool): return String(bool)
        case .dictionary(let dict): return String(describing: dict)
        case .array(let arr): return String(describing: arr)
        case .null: return "null"
        }
    }

    public func toAny() -> Any { value }

    public var asString: String? {
        if case .string(let str) = self { return str }
        return nil
    }

    public var asDictionary: [String: AnyCodable]? {
        if case .dictionary(let dict) = self { return dict }
        return nil
    }

    public var asArray: [AnyCodable]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public init(_ value: Any?) {
        if let anyCodable = value as? AnyCodable {
            self = anyCodable
            return
        }
        if let value = value as? String {
            self = .string(value)
        } else if let value = value as? Double {
            self = .number(value)
        } else if let value = value as? Int {
            self = .number(Double(value))
        } else if let value = value as? Bool {
            self = .boolean(value)
        } else if let value = value as? [String: Any] {
            self = .dictionary(value.mapValues { AnyCodable($0) })
        } else if let value = value as? [Any] {
            self = .array(value.map { AnyCodable($0) })
        } else {
            self = .null
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else {
            self = .null
        }
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
