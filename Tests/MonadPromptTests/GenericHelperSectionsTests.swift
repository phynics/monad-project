import XCTest
@testable import MonadPrompt

final class GenericHelperSectionsTests: XCTestCase {
    
    func testTextSectionInitialization() {
        let section = TextSection(
            id: "system",
            text: "You are an AI.",
            priority: 100,
            strategy: .drop,
            estimatedTokens: 5
        )
        
        XCTAssertEqual(section.id, "system")
        XCTAssertEqual(section.text, "You are an AI.")
        XCTAssertEqual(section.priority, 100)
        
        if case .drop = section.strategy { /* expected */ } else {
            XCTFail("Wrong strategy")
        }
        
        if case .text = section.type { /* expected */ } else {
            XCTFail("Wrong type")
        }
        
        XCTAssertEqual(section.estimatedTokens, 5)
    }
    
    func testTextSectionDefaultEstimatedTokens() {
        // Fallback uses string count / 4
        let text = String(repeating: "char", count: 100) // 400 characters
        let section = TextSection(id: "t1", text: text)
        XCTAssertEqual(section.estimatedTokens, 100)
    }
    
    func testTextSectionRender() async {
        let section = TextSection(id: "t1", text: "Hello")
        let rendered = await section.render()
        XCTAssertEqual(rendered, "Hello")
    }
    
    func testTextSectionRenderEmptyReturnsNil() async {
        let section = TextSection(id: "t1", text: "")
        let rendered = await section.render()
        XCTAssertNil(rendered)
    }
    
    func testEmptySection() async {
        let section = EmptySection()
        
        XCTAssertEqual(section.id, "empty")
        XCTAssertEqual(section.priority, 0)
        XCTAssertEqual(section.estimatedTokens, 0)
        
        let rendered = await section.render()
        XCTAssertNil(rendered)
    }
}
