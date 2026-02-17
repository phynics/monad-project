import XCTest
@testable import MonadPrompt

final class ContextBuilderTests: XCTestCase {
    
    struct MockSection: ContextSection {
        let id: String
        let priority: Int
        let content: String
        let strategy: CompressionStrategy = .keep
        let type: ContextSectionType = .text
        
        var estimatedTokens: Int { content.count }
        
        func render() async -> String? {
            return content
        }
    }
    
    func testExampleBuilder() async {
        let prompt = Prompt {
            MockSection(id: "1", priority: 10, content: "Low Priority")
            MockSection(id: "2", priority: 100, content: "High Priority")
        }
        
        // Should be sorted by priority
        XCTAssertEqual(prompt.sections.count, 2)
        XCTAssertEqual(prompt.sections[0].id, "2")
        XCTAssertEqual(prompt.sections[1].id, "1")
        
        let rendered = await prompt.render()
        XCTAssertTrue(rendered.contains("High Priority"))
        XCTAssertTrue(rendered.contains("Low Priority"))
    }
    
    func testConditionals() async {
        let includeSecret = false
        let includePublic = true
        
        let prompt = Prompt {
            if includeSecret {
                MockSection(id: "secret", priority: 50, content: "Secret")
            }
            
            if includePublic {
                MockSection(id: "public", priority: 50, content: "Public")
            }
        }
        
        XCTAssertEqual(prompt.sections.count, 1)
        XCTAssertEqual(prompt.sections[0].id, "public")
    }
    
    func testLoop() async {
        let items = ["A", "B", "C"]
        
        let prompt = Prompt {
            for item in items {
                MockSection(id: item, priority: 50, content: item)
            }
        }
        
        XCTAssertEqual(prompt.sections.count, 3)
    }
}
