import Foundation
import OSLog

// MARK: - JobQueueContext

/// A ToolContext that provides job queue management capabilities.
///
/// When activated via the gateway tool, this context exposes tools
/// for adding, removing, prioritizing, and managing jobs in a queue.
public final class JobQueueContext: ToolContext, @unchecked Sendable {
    public static let contextId = "job_queue"
    public static let displayName = "Job Queue Manager"
    public static let contextDescription = "Manage a queue of jobs with priorities and statuses"

    private let logger = Logger.tools

    /// Lock for thread-safe access to jobs
    private let lock = NSLock()

    /// The job queue
    private var _jobs: [Job] = []
    private var jobs: [Job] {
        get { lock.withLock { _jobs } }
        set { lock.withLock { _jobs = newValue } }
    }

    /// Context tools (lazy to allow self-reference)
    public private(set) lazy var contextTools: [any Tool] = [
        AddJobTool(context: self),
        RemoveJobTool(context: self),
        ChangePriorityTool(context: self),
        ListJobsTool(context: self),
        UpdateJobStatusTool(context: self),
        ClearQueueTool(context: self),
    ]

    public init() {}

    public func activate() async {
        logger.info("Job Queue context activated")
    }

    public func deactivate() async {
        logger.info("Job Queue context deactivated")
    }

    public func formatState() async -> String {
        if jobs.isEmpty {
            return "**Job Queue**: Empty"
        }

        let sortedJobs = jobs.sorted { $0.priority > $1.priority }
        let jobList = sortedJobs.map { $0.formatted }.joined(separator: "\n")

        return """
            **Job Queue** (\(jobs.count) job\(jobs.count == 1 ? "" : "s")):
            \(jobList)
            """
    }

    public func welcomeMessage() async -> String {
        let toolList = contextTools.map { "- `\($0.id)`: \($0.description)" }.joined(
            separator: "\n")
        return """
            ## Job Queue Manager Activated

            You are now in job queue management mode. Available commands:

            \(toolList)

            > **Note**: Calling any tool outside this context will exit job queue mode.

            \(await formatState())
            """
    }

    // MARK: - Queue Operations

    public func addJob(title: String, description: String?, priority: Int) -> Job {
        let job = Job(title: title, description: description, priority: priority)
        jobs.append(job)
        logger.info("Added job: \(job.id)")
        return job
    }

    public func removeJob(id: UUID) -> Job? {
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            let job = jobs.remove(at: index)
            logger.info("Removed job: \(job.id)")
            return job
        }
        return nil
    }

    public func changePriority(id: UUID, newPriority: Int) -> Job? {
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].priority = newPriority
            jobs[index].updatedAt = Date()
            logger.info("Changed priority for job: \(id) to \(newPriority)")
            return jobs[index]
        }
        return nil
    }

    public func updateStatus(id: UUID, status: Job.Status) -> Job? {
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].status = status
            jobs[index].updatedAt = Date()
            logger.info("Updated status for job: \(id) to \(status.rawValue)")
            return jobs[index]
        }
        return nil
    }

    public func listJobs() -> [Job] {
        return jobs.sorted { $0.priority > $1.priority }
    }

    public func clearQueue() -> Int {
        let count = jobs.count
        jobs.removeAll()
        logger.info("Cleared \(count) jobs from queue")
        return count
    }

    public func getJob(id: UUID) -> Job? {
        jobs.first { $0.id == id }
    }

    public func findJob(idPrefix: String) -> Job? {
        jobs.first { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }
    }

    /// Dequeue the next pending job with highest priority.
    /// Marks the job as in_progress and returns it for processing.
    /// Returns nil if no pending jobs are available.
    public func dequeueNext() -> Job? {
        // Find highest priority pending job
        let pending = jobs.filter { $0.status == .pending }
            .sorted { $0.priority > $1.priority }

        guard let nextJob = pending.first else {
            return nil
        }

        // Find the index in the current jobs array
        let currentJobs = jobs
        guard let index = currentJobs.firstIndex(where: { $0.id == nextJob.id }) else {
            return nil
        }

        // Mark as in progress
        jobs[index].status = .inProgress
        jobs[index].updatedAt = Date()
        let dequeuedJob = jobs[index]
        logger.info("Dequeued job: \(dequeuedJob.title) (priority: \(dequeuedJob.priority))")
        return dequeuedJob
    }

    /// Check if there are pending jobs that can be dequeued
    public var hasPendingJobs: Bool {
        let currentJobs = jobs
        return currentJobs.contains { $0.status == .pending }
    }
}

// MARK: - Context Tools

/// Add a new job to the queue
public struct AddJobTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_add"
    public let name = "Add Job"
    public let description = "Add a new job to the queue"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Job title (required)"],
                "description": ["type": "string", "description": "Job description (optional)"],
                "priority": [
                    "type": "integer",
                    "description": "Priority level (higher = more important, default: 0)",
                ],
            ],
            "required": ["title"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let title = parameters["title"] as? String else {
            return .failure("Missing required parameter: title")
        }

        let description = parameters["description"] as? String
        let priority = parameters["priority"] as? Int ?? 0

        let job = context.addJob(title: title, description: description, priority: priority)
        return .success("Added job: \(job.title) [ID: \(job.id.uuidString.prefix(8))]")
    }
}

/// Remove a job from the queue
public struct RemoveJobTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_remove"
    public let name = "Remove Job"
    public let description = "Remove a job from the queue by ID"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Job ID (full or prefix)"]
            ],
            "required": ["id"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let idString = parameters["id"] as? String else {
            return .failure("Missing required parameter: id")
        }

        // Try to find by prefix first, then by full UUID
        if let job = context.findJob(idPrefix: idString) {
            _ = context.removeJob(id: job.id)
            return .success("Removed job: \(job.title)")
        } else if let uuid = UUID(uuidString: idString),
            let job = context.removeJob(id: uuid)
        {
            return .success("Removed job: \(job.title)")
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// Change job priority
public struct ChangePriorityTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_priority"
    public let name = "Change Priority"
    public let description = "Change the priority of a job"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Job ID (full or prefix)"],
                "priority": ["type": "integer", "description": "New priority level"],
            ],
            "required": ["id", "priority"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let idString = parameters["id"] as? String else {
            return .failure("Missing required parameter: id")
        }
        guard let priority = parameters["priority"] as? Int else {
            return .failure("Missing required parameter: priority")
        }

        // Try to find by prefix first
        if let job = context.findJob(idPrefix: idString) {
            if let updated = context.changePriority(id: job.id, newPriority: priority) {
                return .success("Updated priority for '\(updated.title)' to \(priority)")
            }
        } else if let uuid = UUID(uuidString: idString) {
            if let updated = context.changePriority(id: uuid, newPriority: priority) {
                return .success("Updated priority for '\(updated.title)' to \(priority)")
            }
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// List all jobs
public struct ListJobsTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_list"
    public let name = "List Jobs"
    public let description = "List all jobs in the queue sorted by priority"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let jobs = context.listJobs()
        if jobs.isEmpty {
            return .success("Queue is empty")
        }

        let list = jobs.map { $0.formatted }.joined(separator: "\n")
        return .success("Jobs (\(jobs.count)):\n\(list)")
    }
}

/// Update job status
public struct UpdateJobStatusTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_status"
    public let name = "Update Status"
    public let description =
        "Update the status of a job (pending, in_progress, completed, cancelled)"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Job ID (full or prefix)"],
                "status": [
                    "type": "string", "enum": ["pending", "in_progress", "completed", "cancelled"],
                ],
            ],
            "required": ["id", "status"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let idString = parameters["id"] as? String else {
            return .failure("Missing required parameter: id")
        }
        guard let statusString = parameters["status"] as? String,
            let status = Job.Status(rawValue: statusString)
        else {
            return .failure("Invalid status. Use: pending, in_progress, completed, or cancelled")
        }

        // Try to find by prefix first
        if let job = context.findJob(idPrefix: idString) {
            if let updated = context.updateStatus(id: job.id, status: status) {
                return .success("Updated '\(updated.title)' status to \(status.rawValue)")
            }
        } else if let uuid = UUID(uuidString: idString) {
            if let updated = context.updateStatus(id: uuid, status: status) {
                return .success("Updated '\(updated.title)' status to \(status.rawValue)")
            }
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// Clear all jobs
public struct ClearQueueTool: ContextTool, @unchecked Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_clear"
    public let name = "Clear Queue"
    public let description = "Remove all jobs from the queue"
    public let requiresPermission = false

    private let context: JobQueueContext

    init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let count = context.clearQueue()
        return .success("Cleared \(count) job\(count == 1 ? "" : "s") from queue")
    }
}
