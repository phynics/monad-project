import MonadShared
import Foundation

public func getTestWorkspaceRoot() -> URL {
    let fileManager = FileManager.default
    // Use a robust temp directory for tests if possible, but keeping original logic for now
    let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let testWorkspacesDir = currentDir.appendingPathComponent(".test_workspaces", isDirectory: true)
    try? fileManager.createDirectory(at: testWorkspacesDir, withIntermediateDirectories: true)
    return testWorkspacesDir
}
