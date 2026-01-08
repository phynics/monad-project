import XCTest
@testable import MonadCore

final class MessageNodeTests: XCTestCase {
    
    func testConstructForestLinear() {
        // User -> Assistant -> User
        let m1 = Message(content: "1", role: .user)
        let m2 = Message(content: "2", role: .assistant, parentId: m1.id)
        let m3 = Message(content: "3", role: .user, parentId: m2.id)
        
        let messages = [m1, m2, m3]
        let forest = [MessageNode].constructForest(from: messages)
        
        XCTAssertEqual(forest.count, 1)
        XCTAssertEqual(forest[0].id, m1.id)
        XCTAssertEqual(forest[0].children.count, 1)
        XCTAssertEqual(forest[0].children[0].id, m2.id)
        XCTAssertEqual(forest[0].children[0].children.count, 1)
        XCTAssertEqual(forest[0].children[0].children[0].id, m3.id)
    }
    
    func testConstructForestBranching() {
        // Root -> Child1
        //      -> Child2
        let root = Message(content: "Root", role: .user)
        let c1 = Message(content: "C1", role: .assistant, parentId: root.id)
        let c2 = Message(content: "C2", role: .assistant, parentId: root.id)
        
        let messages = [root, c1, c2]
        let forest = [MessageNode].constructForest(from: messages)
        
        XCTAssertEqual(forest.count, 1)
        XCTAssertEqual(forest[0].id, root.id)
        XCTAssertEqual(forest[0].children.count, 2)
        XCTAssertTrue(forest[0].children.contains { $0.id == c1.id })
        XCTAssertTrue(forest[0].children.contains { $0.id == c2.id })
    }
    
    func testConstructForestOutOfOrder() {
        // Grandchild comes before Parent in array? 
        // Logic relies on map population.
        // G (parent: C) -> C (parent: R) -> R
        
        let r = Message(content: "R", role: .user)
        let c = Message(content: "C", role: .assistant, parentId: r.id)
        let g = Message(content: "G", role: .user, parentId: c.id)
        
        let messages = [g, c, r] // Reverse order
        let forest = [MessageNode].constructForest(from: messages)
        
        XCTAssertEqual(forest.count, 1)
        XCTAssertEqual(forest[0].id, r.id)
        XCTAssertEqual(forest[0].children.count, 1)
        XCTAssertEqual(forest[0].children[0].id, c.id)
        XCTAssertEqual(forest[0].children[0].children.count, 1)
        XCTAssertEqual(forest[0].children[0].children[0].id, g.id)
    }
    
    func testFlattenedWithBranching() {
        // User says "Hi" -> Assistant says "A" (id: 2)
        // User regenerates -> Assistant says "B" (id: 3)
        // Both 2 and 3 are children of 1.
        
        let m1 = Message(content: "Hi", role: .user)
        let m2 = Message(content: "A", role: .assistant, parentId: m1.id)
        let m3 = Message(content: "B", role: .assistant, parentId: m1.id)
        
        // Order in input array determines order in children array
        let messages = [m1, m2, m3]
        let forest = [MessageNode].constructForest(from: messages)
        
        let flat = forest.flattened()
        
        // Current implementation flattens ALL branches sequentially
        XCTAssertEqual(flat.count, 3)
        XCTAssertEqual(flat[0].content, "Hi")
        XCTAssertEqual(flat[1].content, "A")
        XCTAssertEqual(flat[2].content, "B")
        
        // This confirms that if we have branching, the context sent to LLM 
        // via `flattened()` will include BOTH responses, which is likely incorrect 
        // for a standard chat context.
        // TODO: Implement `activePath()` or similar if branching is supported.
    }
}
