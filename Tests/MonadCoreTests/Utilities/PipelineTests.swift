import Testing
import Foundation
import Logging
@testable import MonadCore

@Suite final class PipelineTests {
    
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
    
    @Test

    
    func testDefaultID() {
        let stage = DefaultIDStage()
        #expect(stage.id == "DefaultIDStage")
    }
    
    @Test

    
    func testPipelineExecutionWithLogger() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .withLogger(Logger(label: "test"))
            .add(MockStage(id: "stage1", value: "one"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        #expect(context.values == ["one"])
    }
    
    @Test

    
    func testPipelineExecution() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(MockStage(id: "stage1", value: "one"))
            .add(MockStage(id: "stage2", value: "two"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        #expect(context.values == ["one", "two"])
    }
    
    @Test

    
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
            Issue.record("Pipeline should have thrown an error")
        } catch let PipelineError.stageFailed(id, error) {
            #expect(id == "errorStage")
            #expect(error as? MockError == .someError)
            #expect(context.values == ["one"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test

    
    func testPipelineCleanup() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(MockStage(id: "stage1", value: "one"))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))
        
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        #expect(context.values == ["one", "clean"])
    }
    
    @Test

    
    func testPipelineCleanupAfterFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(ErrorStage(id: "errorStage", error: MockError.someError))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            Issue.record("Should have thrown error")
        } catch {
            #expect(context.values == ["clean"])
        }
    }
    
    @Test

    
    func testPipelineCleanupFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .cleanup(ErrorStage(id: "cleanupError", error: MockError.someError))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            Issue.record("Should have thrown error")
        } catch let PipelineError.cleanupFailed(id, _) {
            #expect(id == "cleanupError")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test

    
    func testPipelineCleanupFailureDoesNotOverridePrimaryError() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
            .add(ErrorStage(id: "primaryError", error: MockError.someError))
            .cleanup(ErrorStage(id: "cleanupError", error: MockError.someError))
        
        var context = TestContext()
        
        // When / Then
        do {
            try await pipeline.execute(&context)
            Issue.record("Should have thrown error")
        } catch let PipelineError.stageFailed(id, _) {
            #expect(id == "primaryError")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test

    
    func testEmptyPipeline() async throws {
        // Given
        let pipeline = Pipeline<TestContext>()
        var context = TestContext()
        
        // When
        try await pipeline.execute(&context)
        
        // Then
        #expect(context.values.isEmpty)
    }
}
