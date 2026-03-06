import MonadShared

/// Re-export the free function
public func toJsonString(_ dict: [String: AnyCodable]) throws -> String {
    try MonadShared.toJsonString(dict)
}
