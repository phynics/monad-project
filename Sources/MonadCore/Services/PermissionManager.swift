import Foundation
import OSLog

public enum PermissionResponse: Sendable {
    case approve
    case deny
    case approveForSession(path: String)
}

public protocol PermissionDelegate: AnyObject, Sendable {
    func requestPermission(tool: Tool, arguments: [String: String]) async -> PermissionResponse
}

public actor PermissionManager {
    private weak var delegate: PermissionDelegate?
    private var allowedPaths: [String] = []
    private let logger = Logger(subsystem: "com.monad.core", category: "PermissionManager")

    public init(delegate: PermissionDelegate? = nil) {
        self.delegate = delegate
    }

    public func setDelegate(_ delegate: PermissionDelegate) {
        self.delegate = delegate
    }

    public func checkPermission(tool: Tool, arguments: [String: Any], workingDirectory: String) async -> Bool {
        guard tool.requiresPermission else { return true }

        // Convert arguments to String dictionary for Sendable compliance
        var stringArgs: [String: String] = [:]
        for (key, value) in arguments {
            stringArgs[key] = String(describing: value)
        }

        // Extract path from arguments if present
        let pathKeys = ["path", "filename", "file", "directory", "root"]
        var path: String?
        for key in pathKeys {
            if let p = arguments[key] as? String {
                path = p
                break
            }
        }

        // Resolve absolute path
        let absolutePath: String
        if let p = path {
            if p.hasPrefix("/") {
                absolutePath = p
            } else if p.hasPrefix("~") {
                absolutePath = (p as NSString).expandingTildeInPath
            } else {
                absolutePath = URL(fileURLWithPath: workingDirectory).appendingPathComponent(p).path
            }
        } else {
            absolutePath = workingDirectory
        }

        // Check if we have session-wide permission for the path
        if isPathAllowed(absolutePath) {
            logger.info("Permission automatically granted for path: \(absolutePath)")
            return true
        }

        guard let delegate = delegate else {
            logger.warning("No permission delegate set, denying permission for \(tool.name)")
            return false
        }

        logger.info("Requesting permission for tool: \(tool.name)")
        let response = await delegate.requestPermission(tool: tool, arguments: stringArgs)

        switch response {
        case .approve:
            logger.info("Permission granted once for \(tool.name)")
            return true
        case .deny:
            logger.info("Permission denied for \(tool.name)")
            return false
        case .approveForSession(let allowedPath):
            logger.info("Permission granted for session for path: \(allowedPath)")
            allowedPaths.append(allowedPath)
            return true
        }
    }

    private func isPathAllowed(_ path: String) -> Bool {
        // Normalize path checking logic
        let standardPath = (path as NSString).standardizingPath

        for allowed in allowedPaths {
            let standardAllowed = (allowed as NSString).standardizingPath

            if standardPath == standardAllowed {
                return true
            }

            // Ensure strict directory prefix matching
            // /foo/bar matches /foo/bar/baz
            // /foo/bar DOES NOT match /foo/bar_secret
            // Handle root specially since standardAllowed "/" + "/" is "//"
            let prefix = standardAllowed.hasSuffix("/") ? standardAllowed : standardAllowed + "/"
            if standardPath.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
}
