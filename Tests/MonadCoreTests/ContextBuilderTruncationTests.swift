import XCTest
@testable import MonadCore
@testable import MonadPrompt
import MonadShared

final class ContextBuilderTruncationTests: XCTestCase {
    
    func testChatHistoryTruncation() async {
        // Create 10 messages of approx 10 tokens each + overhead
        let messages = (1...10).map { i in
            Message(content: "Message \(i) content", role: .user)
        }
        
        let history = ChatHistory(messages)
        let totalTokens = history.estimatedTokens
        
        // 1. Test no truncation
        let constrainedUnchanged = history.constrained(to: totalTokens + 100)
        XCTAssertTrue(constrainedUnchanged is ChatHistory)
        if let h = constrainedUnchanged as? ChatHistory {
            XCTAssertEqual(h.messages.count, 10)
        }
        
        // 2. Test truncation to half
        // Estimate: 10 messages * ~5 tokens = 50. Let's say we limit to 20.
        // It should keep the LAST few messages.
        let limit = totalTokens / 2
        let constrained = history.constrained(to: limit)
        
        XCTAssertTrue(constrained is ChatHistory)
        if let h = constrained as? ChatHistory {
            XCTAssertLessThan(h.messages.count, 10)
            XCTAssertGreaterThan(h.messages.count, 0)
            // Should keep the last message
            XCTAssertEqual(h.messages.last?.content, "Message 10 content")
        }
    }
    
    func testContextNotesTruncation() async {
        let longNote = String(repeating: "A long note content. ", count: 50)
        let file = ContextFile(name: "test", content: longNote, source: "test")
        let section = ContextNotes([file])
        
        // 1. Test render full
        let fullRender = await section.render()
        XCTAssertNotNil(fullRender)
        
        // 2. Test render constrained
        // Limit to 10 tokens (approx 40 chars)
        let constrainedRender = await section.render(constrainedTo: 10)
        XCTAssertNotNil(constrainedRender)
        
        let constrainedCount = constrainedRender?.count ?? 0
        let fullCount = fullRender?.count ?? 0
        
        XCTAssertTrue(constrainedRender?.contains("[Truncated]") == true)
        XCTAssertLessThan(constrainedCount, fullCount)
    }
    
    func testTokenBudgetApplication() async {
        // Setup: History (Priority 70, Truncatable), System (Priority 100, Keep)
        let system = SystemInstructions("System instructions") // approx 3-5 tokens
        
        // Truncatable history
        let messages = (1...20).map { Message(content: "msg \($0)", role: .user) } 
        let history = ChatHistory(messages)
        
        let sections: [ContextSection] = [system, history]
        
        // Budget calculation:
        // System: ~3 tokens. 
        // History: 20 messages * (~3 tokens) = ~60 tokens.
        // Total est: 63.
        // Limit: 30. 
        // Expect: System kept (3), History gets remaining (27).
        
        let budget = TokenBudget(maxTokens: 30, reserveForResponse: 0)
        let processed = await budget.apply(to: sections)
        
        XCTAssertEqual(processed.count, 2)
        
        // Check System (should be same object/type)
        let processedSystem = processed.first(where: { $0.id == "system" })
        XCTAssertNotNil(processedSystem)
        XCTAssertTrue(processedSystem is SystemInstructions)
        
        // Check History (should be truncated ChatHistory)
        let processedHistory = processed.first(where: { $0.id == "chat_history" })
        XCTAssertNotNil(processedHistory)
        
        if let h = processedHistory as? ChatHistory {
             XCTAssertLessThan(h.messages.count, 20)
             XCTAssertGreaterThan(h.messages.count, 0)
             // Should still be valid history
        } else {
            XCTFail("History should preserve ChatHistory type")
        }
    }
}
