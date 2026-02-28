import XCTest
@testable import MonadPrompt

struct MinimalSection: ContextSection {
    let id: String = "min"
    let priority: Int = 1
    let estimatedTokens: Int = 100
    
    func render() async -> String? {
        return "minimal text"
    }
}

final class ContextSectionTests: XCTestCase {
    
    func testDefaultImplementations() async {
        let section = MinimalSection()
        
        // Default strategy should be .keep
        if case .keep = section.strategy { /* expected */ } else {
            XCTFail("Default strategy should be .keep")
        }
        
        // Default type should be .text
        if case .text = section.type { /* expected */ } else {
            XCTFail("Default type should be .text")
        }
        
        // Default render(constrainedTo:) just calls render()
        let constrainedRender = await section.render(constrainedTo: 50)
        XCTAssertEqual(constrainedRender, "minimal text")
    }
    
    func testConstrainedSection() async {
        let base = MinimalSection() // size 100
        let constrained = ConstrainedSection(wrapped: base, limit: 50)
        
        XCTAssertEqual(constrained.id, "min")
        XCTAssertEqual(constrained.priority, 1)
        XCTAssertEqual(constrained.estimatedTokens, 50) // capped by limit
        
        if case .keep = constrained.strategy { /* expected */ } else {
            XCTFail("Strategy must pass through")
        }
        
        // Nesting constraints
        let doublyConstrained = constrained.constrained(to: 30) as! ConstrainedSection
        XCTAssertEqual(doublyConstrained.limit, 30)
        XCTAssertEqual(doublyConstrained.estimatedTokens, 30)
        
        // If we constrain to a larger amount, limit should reflect the min
        let largerConstrained = doublyConstrained.constrained(to: 100) as! ConstrainedSection
        XCTAssertEqual(largerConstrained.limit, 30)
    }
}
