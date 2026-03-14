import Testing
import Foundation
import Logging
@testable import MonadCore

@Suite final class PipelineTests {

    final class TestContext: @unchecked Sendable {
        var values: [String] = []
    }

    struct MockStage: PipelineStage {
        typealias Event = String
        let id: String
        let value: String
        let eventToEmit: String?

        init(id: String, value: String, eventToEmit: String? = nil) {
            self.id = id
            self.value = value
            self.eventToEmit = eventToEmit
        }

        func process(_ context: TestContext) async throws -> AsyncThrowingStream<String, Error> {
            context.values.append(value)
            return AsyncThrowingStream { continuation in
                if let event = eventToEmit {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    struct DefaultIDStage: PipelineStage {
        typealias Event = Never
        func process(_ context: TestContext) async throws -> AsyncThrowingStream<Never, Error> {
            return AsyncThrowingStream { $0.finish() }
        }
    }

    struct ErrorStage<E: Sendable>: PipelineStage {
        typealias Event = E
        let id: String
        let error: Error

        func process(_ context: TestContext) async throws -> AsyncThrowingStream<E, Error> {
            throw error
        }
    }

    enum MockError: Error, LocalizedError, Equatable {
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
        let pipeline = Pipeline<TestContext, String>()
            .withLogger(Logger(label: "test"))
            .add(MockStage(id: "stage1", value: "one"))

        let context = TestContext()

        // When
        let stream = pipeline.execute(context)
        for try await _ in stream {}

        // Then
        #expect(context.values == ["one"])
    }

    @Test
    func testPipelineExecution() async throws {
        // Given
        let pipeline = Pipeline<TestContext, String>()
            .add(MockStage(id: "stage1", value: "one"))
            .add(MockStage(id: "stage2", value: "two"))

        let context = TestContext()

        // When
        let stream = pipeline.execute(context)
        for try await _ in stream {}

        // Then
        #expect(context.values == ["one", "two"])
    }

    @Test
    func testPipelineEvents() async throws {
        // Given
        let pipeline = Pipeline<TestContext, String>()
            .add(MockStage(id: "stage1", value: "one", eventToEmit: "event1"))
            .add(MockStage(id: "stage2", value: "two", eventToEmit: "event2"))

        let context = TestContext()
        var events: [String] = []

        // When
        let stream = pipeline.execute(context)
        for try await event in stream {
            events.append(event)
        }

        // Then
        #expect(context.values == ["one", "two"])
        #expect(events == ["event1", "event2"])
    }

    @Test
    func testPipelineErrorHandling() async throws {
        // Given
        let pipeline = Pipeline<TestContext, String>()
            .add(MockStage(id: "stage1", value: "one"))
            .add(ErrorStage<String>(id: "errorStage", error: MockError.someError))
            .add(MockStage(id: "stage2", value: "two"))

        let context = TestContext()

        // When / Then
        do {
            let stream = pipeline.execute(context)
            for try await _ in stream {}
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
        let pipeline = Pipeline<TestContext, String>()
            .add(MockStage(id: "stage1", value: "one"))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))

        let context = TestContext()

        // When
        let stream = pipeline.execute(context)
        for try await _ in stream {}

        // Then
        #expect(context.values == ["one", "clean"])
    }

    @Test
    func testPipelineCleanupAfterFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext, String>()
            .add(ErrorStage<String>(id: "errorStage", error: MockError.someError))
            .cleanup(MockStage(id: "cleanup1", value: "clean"))

        let context = TestContext()

        // When / Then
        do {
            let stream = pipeline.execute(context)
            for try await _ in stream {}
            Issue.record("Should have thrown error")
        } catch {
            #expect(context.values == ["clean"])
        }
    }

    @Test
    func testPipelineCleanupFailure() async throws {
        // Given
        let pipeline = Pipeline<TestContext, Never>()
            .cleanup(ErrorStage<Never>(id: "cleanupError", error: MockError.someError))

        let context = TestContext()

        // When / Then
        do {
            let stream = pipeline.execute(context)
            for try await _ in stream {}
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
        let pipeline = Pipeline<TestContext, Never>()
            .add(ErrorStage<Never>(id: "primaryError", error: MockError.someError))
            .cleanup(ErrorStage<Never>(id: "cleanupError", error: MockError.someError))

        let context = TestContext()

        // When / Then
        do {
            let stream = pipeline.execute(context)
            for try await _ in stream {}
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
        let pipeline = Pipeline<TestContext, Never>()
        let context = TestContext()

        // When
        let stream = pipeline.execute(context)
        for try await _ in stream {}

        // Then
        #expect(context.values.isEmpty)
    }
}
