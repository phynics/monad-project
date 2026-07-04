import Foundation
@testable import MonadServer
import MonadShared
import PKShared
import PositronicKit
import Testing

/// Contract test asserting `LocalWorkspace.listFiles` scopes enumeration to the requested
/// subdirectory, matching `PKTestSupport.MockLocalWorkspace` (see PKR-15). Production previously
/// validated `path` but always enumerated from the workspace root, silently ignoring the
/// requested subdirectory.
struct LocalWorkspaceTests {
    @Test("listFiles scopes enumeration to the requested subdirectory")
    func listFilesScopesToRequestedPath() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "root".write(to: rootURL.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)

        let subDir = rootURL.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "nested".write(to: subDir.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

        let reference = WorkspaceReference(
            uri: WorkspaceURI(host: "local", path: rootURL.path),
            location: .runtime,
            rootPath: rootURL.path
        )
        let workspace = try LocalWorkspace(reference: reference)

        // Returned paths stay root-relative (not relative to the requested `path`) because callers
        // feed listFiles' output straight into readFile/writeFile, which resolve paths relative to
        // the workspace root.
        let scoped = try await workspace.listFiles(path: "sub")
        #expect(scoped == ["sub/nested.txt"])

        let rootListing = try await workspace.listFiles(path: ".")
        #expect(Set(rootListing) == Set(["root.txt", "sub/nested.txt"]))
    }
}
