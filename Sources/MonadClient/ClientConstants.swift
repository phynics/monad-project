import MonadShared

// MARK: - Filesystem Tool References

/// Standard filesystem tool references for client registration
public enum ClientConstants {
    public static let filesystemToolReferences: [ToolReference] = [
        .known(id: "cat"),
        .known(id: "ls"),
        .known(id: "grep"),
        .known(id: "search_files"),
        .known(id: "find"),
        .known(id: "inspect_file"),
        .custom(
            WorkspaceToolDefinition(
                id: "dummy_tool",
                name: "Dummy Tool Text",
                description: "A test tool",
                parametersSchema: [:],
                contextInjection: "This tool does absolutely nothing but tests context injection."
            )
        )
    ]
}

// MARK: - Re-exports for CLI consumers

public typealias DebugSnapshot = MonadShared.DebugSnapshot
public typealias SerializationUtils = MonadShared.SerializationUtils
