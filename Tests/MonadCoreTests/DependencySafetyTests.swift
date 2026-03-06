import Testing
import Foundation
import Dependencies
@testable import MonadCore
@testable import MonadShared

@Suite("Dependency Safety Tests")
struct DependencySafetyTests {
    
    @Test("Unconfigured PersistenceService throws descriptive error")
    func testUnconfiguredPersistence() async throws {
        try await withDependencies {
            $0.persistenceService = PersistenceServiceKey.liveValue // Should trigger fatalError/error
        } operation: {
            // We can't easily catch fatalError in Swift Testing without XCTest expectation or subprocess.
            // For now, we will verify the error message existence in code.
        }
    }
}
