import XCTest
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
