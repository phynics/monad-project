import Foundation

/// Internal health status for core services.
public enum HealthStatus: String, Sendable, Codable {
    case ok
    case degraded
    case down
}
