import MonadShared
@_exported import enum MonadShared.AnyCodable

/// Re-export the free function
public func toJsonString(_ dict: [String: AnyCodable]) throws -> String {
    try MonadShared.toJsonString(dict)
}
