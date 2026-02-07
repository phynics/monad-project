import Foundation

/// Protocol for services that can report their health status.
public protocol HealthCheckable: Sendable {
    /// Returns the current cached health status.
    var healthStatus: HealthStatus { get async }
    
    /// Returns any additional details about the health status.
    var healthDetails: [String: String]? { get async }
    
    /// Performs a fresh health check and returns the result.
    func checkHealth() async -> HealthStatus
}