import XCTest
@testable import MonadCore
import Foundation

final class WorkspaceURITests: XCTestCase {
    func testWorkspaceURIParsingLocal() {
        let uri = WorkspaceURI(parsing: "local:/Users/test/Code/project")
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri?.host, "local")
        XCTAssertEqual(uri?.path, "/Users/test/Code/project")
    }
    
    func testWorkspaceURIParsingHost() {
        let uri = WorkspaceURI(parsing: "monad-server:/sessions/abc")
        XCTAssertNotNil(uri)
        XCTAssertEqual(uri?.host, "monad-server")
        XCTAssertEqual(uri?.path, "/sessions/abc")
        XCTAssertTrue(uri?.isServer == true)
        XCTAssertFalse(uri?.isClient == true)
    }
    
    func testWorkspaceURIParsingInvalid() {
        let uri = WorkspaceURI(parsing: "invalid/some/path")
        XCTAssertNil(uri)
    }
    
    func testWorkspaceURIToString() {
        let uri = WorkspaceURI(host: "local", path: "/var/tmp")
        XCTAssertEqual(uri.description, "local:/var/tmp")
    }
    
    func testWorkspaceURIEquality() {
        let uri1 = WorkspaceURI(host: "local", path: "/var/tmp")
        let uri2 = WorkspaceURI(parsing: "local:/var/tmp")
        let uri3 = WorkspaceURI(host: "macbook", path: "/var/tmp")
        
        XCTAssertEqual(uri1, uri2)
        XCTAssertNotEqual(uri1, uri3)
    }
}
