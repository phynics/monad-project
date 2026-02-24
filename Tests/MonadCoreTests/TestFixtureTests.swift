import Testing
import Foundation
@testable import MonadCore

@Suite("Test Fixtures and Builders Tests")
struct TestFixtureTests {
    
    @Test("Message Builder creates valid message with defaults")
    func testMessageBuilder() {
        let msg = Message.fixture(content: "Custom Content")
        #expect(msg.content == "Custom Content")
        #expect(msg.role == .user) // Default
    }
    
    @Test("Memory Builder creates valid memory")
    func testMemoryBuilder() {
        let memory = Memory.fixture(title: "Important Fact")
        #expect(memory.title == "Important Fact")
        #expect(!memory.content.isEmpty)
    }
    
    @Test("Job Builder creates valid job")
    func testJobBuilder() {
        let job = Job.fixture(priority: 10)
        #expect(job.priority == 10)
        #expect(job.status == .pending)
    }
}
