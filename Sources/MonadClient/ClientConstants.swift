import MonadShared

// MARK: - Filesystem Tool References

/// Standard filesystem tool references for client registration
public enum ClientConstants {
    public static let readOnlyToolReferences: [ToolReference] = [
        .known(id: "cat"),
        .known(id: "ls"),
        .known(id: "grep"),
        .known(id: "search_files"),
        .known(id: "find"),
        .custom(
            WorkspaceToolDefinition(
                id: "inspect_file",
                name: "Inspect File",
                description: "Determine file type and basic metadata using the unix 'file' command.",
                parametersSchema: InspectFileTool().parametersSchema
            )
        ),
        .custom(
            WorkspaceToolDefinition(
                id: "request_write_access",
                name: "Request Write Access",
                description: "Request permission from the user to modify files in the active workspace. "
                    + "Call this tool when you need to create, write, edit, or delete files "
                    + "but the workspace is currently in read-only mode.",
                parametersSchema: RequestWriteAccessTool().parametersSchema
            )
        ),
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

    public static let readWriteToolReferences: [ToolReference] = [
        // Placeholder for future write tools
        .known(id: "write_file"),
        .known(id: "edit_file"),
        .known(id: "delete_file")
    ]
}

// MARK: - Re-exports for CLI consumers

public typealias DebugSnapshot = MonadShared.DebugSnapshot
public typealias SerializationUtils = MonadShared.SerializationUtils
