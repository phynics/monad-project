import Foundation
import Observation
import MonadCore

@Observable
public final class PerformanceMetrics {
    public var sessionSpeeds: [Double] = []
    public var averageSpeed: Double {
        guard !sessionSpeeds.isEmpty else { return 0 }
        return sessionSpeeds.reduce(0, +) / Double(sessionSpeeds.count)
    }
    
    public var lastSpeed: Double? {
        sessionSpeeds.last
    }
    
    public var isSlow: Bool {
        guard sessionSpeeds.count >= 1, averageSpeed > 0 else { return false }
        guard let last = lastSpeed else { return false }
        return last < (averageSpeed * 0.75)
    }
    
    public init() {}
    
    public func recordSpeed(_ speed: Double) {
        sessionSpeeds.append(speed)
    }
    
    public func clear() {
        sessionSpeeds = []
    }
}
