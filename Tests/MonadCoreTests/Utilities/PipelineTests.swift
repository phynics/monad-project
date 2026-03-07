import XCTest
import Logging
@testable import MonadCore

final class PipelineTests: XCTestCase {
    
    struct TestContext {
        var values: [String] = []
    }
    
    struct MockStage: PipelineStage {
        let id: String
        let value: String
        
        func process(_ context: inout TestContext) async throws {
            context.values.append(value)
        }
    }
    
    struct DefaultIDStage: PipelineStage {
        func process(_ context: inout TestContext) async throws {}
    }
    
    struct ErrorStage: PipelineStage {
        let id: String
        let error: Error
        
        func process(_ context: inout TestContext) async throws {
            throw error
        }
    }
    
    enum MockError: Error, LocalizedError {
        case someError
        
        var errorDescription: String? {
            return "Mock error occurred"
        }
    }
    
    func testDefaultID() {
        let stage = DefaultIDStage()
        XCTAssertEqual(stage.id, "DefaultIDStage")
    }
    
    func testPipelineExecutionWithLogger() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .withLogger(Logger(label: "test"))
            .add(MockStage(id: "stage1", value: "one"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        XCTAssertEqual(context.values, ["one"])
    }
    
    func testPipelineExecution() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(MockStage(id: "stage1", value: "one"))
            .add(MockStage(id: "stage2", value: "two"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        XCTAssertEqual(context.values, ["one", "two"])
    }
    
    func testPipelineErrorHandling() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(MockStage(id: "stage1", value: "one"))
            .add(ErrorStage(id: "errorStage", error: MockError.someError))
            .add(MockStage(id: "stage2", value: "two"))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            XCTFail("Pipeline should have thrown an error")
        } catch let PipelineError.stageFailed(id, error) {
            XCTAssertEqual(id, "errorStage")
            XCTAssertEqual(error as? MockError, .someError)
            XCTAssertEqual(context.values, ["one"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testPipelineCleanup() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(MockStage(id: "stage1", value: "one"))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        XCTAssertEqual(context.values, ["one", "clean"])
    }
    
    func testPipelineCleanupAfterFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(ErrorStage(id: "errorStage", error: MockError.someError))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(context.values, ["clean"])
        }
    }
    
    func testPipelineCleanupFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .cleanup(ErrorStage(id: "cleanupError", error: MockError.someError))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            XCTFail("Should have thrown error")
        } catch let PipelineError.cleanupFailed(id, _) {
            XCTAssertEqual(id, "cleanupError")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testPipelineCleanupFailureDoesNotOverridePrimaryError() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(ErrorStage(id: "primaryError", error: MockError.someError))
            .cleanup(ErrorStage(id: "cleanupError", error: MockError.someError))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            XCTFail("Should have thrown error")
        } catch let PipelineError.stageFailed(id, _) {
            XCTAssertEqual(id, "primaryError")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testEmptyPipeline() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        XCTAssertTrue(context.values.isEmpty)
    }
}
