import Foundation
import Logging

// MARK: - JobQueueContext

/// A ToolContext that provides job queue management capabilities.
///
/// When activated via the gateway tool, this context exposes tools
/// for adding, removing, prioritizing, and managing jobs in a queue.
public actor JobQueueContext: ToolContext {
    public static let contextId = "job_queue"
    public static let displayName = "Job Queue Manager"
    public static let contextDescription = "Manage a queue of jobs with priorities and statuses"

    private let logger = Logger.tools
    private let persistenceService: any PersistenceServiceProtocol
    private let sessionId: UUID

    public var contextTools: [any Tool] {
        [
            AddJobTool(context: self),
            RemoveJobTool(context: self),
            ChangePriorityTool(context: self),
            ListJobsTool(context: self),
            UpdateJobStatusTool(context: self),
            ClearQueueTool(context: self),
        ]
    }

    public init(persistenceService: any PersistenceServiceProtocol, sessionId: UUID) {
        self.persistenceService = persistenceService
        self.sessionId = sessionId
    }

    public func activate() async {
        logger.info("Job Queue context activated")
    }

    public func deactivate() async {
        logger.info("Job Queue context deactivated")
    }

    public func formatState() async -> String {
        guard let jobs = try? await persistenceService.fetchJobs(for: sessionId) else {
            return "**Job Queue**: Error fetching jobs"
        }
        
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

    public func addJob(title: String, description: String?, priority: Int) async throws -> Job {
        let job = Job(sessionId: sessionId, title: title, description: description, priority: priority)
        try await persistenceService.saveJob(job)
        logger.info("Added job: \(job.id)")
        return job
    }
    
    public func launchSubagent(request: AddJobRequest) async throws -> Job {
        let job = Job(
            sessionId: sessionId,
            parentId: request.parentId,
            title: request.title,
            description: request.description,
            priority: request.priority,
            agentId: request.agentId ?? "default"
        )
        try await persistenceService.saveJob(job)
        logger.info("Launched subagent job: \(job.id) (agent: \(job.agentId))")
        return job
    }

    public func removeJob(id: UUID) async throws -> Job? {
        if let job = try await persistenceService.fetchJob(id: id) {
            try await persistenceService.deleteJob(id: id)
            logger.info("Removed job: \(id)")
            return job
        }
        return nil
    }

    public func changePriority(id: UUID, newPriority: Int) async throws -> Job? {
        if var job = try await persistenceService.fetchJob(id: id) {
            job.priority = newPriority
            job.updatedAt = Date()
            try await persistenceService.saveJob(job)
            logger.info("Changed priority for job: \(id) to \(newPriority)")
            return job
        }
        return nil
    }

    public func updateStatus(id: UUID, status: Job.Status) async throws -> Job? {
        if var job = try await persistenceService.fetchJob(id: id) {
            job.status = status
            job.updatedAt = Date()
            try await persistenceService.saveJob(job)
            logger.info("Updated status for job: \(id) to \(status.rawValue)")
            return job
        }
        return nil
    }

    public func listJobs() async throws -> [Job] {
        return try await persistenceService.fetchJobs(for: sessionId).sorted { $0.priority > $1.priority }
    }

    public func clearQueue() async throws -> Int {
        let jobs = try await persistenceService.fetchJobs(for: sessionId)
        for job in jobs {
            try await persistenceService.deleteJob(id: job.id)
        }
        logger.info("Cleared \(jobs.count) jobs from queue")
        return jobs.count
    }

    public func getJob(id: UUID) async throws -> Job? {
        try await persistenceService.fetchJob(id: id)
    }

    public func findJob(idPrefix: String) async throws -> Job? {
        let jobs = try await persistenceService.fetchJobs(for: sessionId)
        return jobs.first { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }
    }

    /// Dequeue the next pending job with highest priority.
    /// Marks the job as in_progress and returns it for processing.
    /// Returns nil if no pending jobs are available.
    public func dequeueNext() async throws -> Job? {
        let jobs = try await persistenceService.fetchJobs(for: sessionId)
        
        // Find highest priority pending job
        let pending = jobs.filter { $0.status == .pending }
            .sorted { $0.priority > $1.priority }

        guard var nextJob = pending.first else {
            return nil
        }

        // Mark as in progress
        nextJob.status = .inProgress
        nextJob.updatedAt = Date()
        try await persistenceService.saveJob(nextJob)
        
        logger.info("Dequeued job: \(nextJob.title) (priority: \(nextJob.priority))")
        return nextJob
    }

    /// Check if there are pending jobs that can be dequeued
    public func hasPendingJobs() async throws -> Bool {
        let jobs = try await persistenceService.fetchJobs(for: sessionId)
        return jobs.contains { $0.status == .pending }
    }
    
    public func formatPinnedState() async -> String? {
        nil
    }
}

// MARK: - Context Tools

/// Add a new job to the queue
public struct AddJobTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_add"
    public let name = "Add Job"
    public let description = "Add a new job to the queue"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
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

        let job = try await context.addJob(title: title, description: description, priority: priority)
        return .success("Added job: \(job.title) [ID: \(job.id.uuidString.prefix(8))]")
    }
}

/// Remove a job from the queue
public struct RemoveJobTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_remove"
    public let name = "Remove Job"
    public let description = "Remove a job from the queue by ID"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
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
        if let job = try await context.findJob(idPrefix: idString) {
            _ = try await context.removeJob(id: job.id)
            return .success("Removed job: \(job.title)")
        } else if let uuid = UUID(uuidString: idString),
            let job = try await context.removeJob(id: uuid)
        {
            return .success("Removed job: \(job.title)")
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// Change job priority
public struct ChangePriorityTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_priority"
    public let name = "Change Priority"
    public let description = "Change the priority of a job"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
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
        if let job = try await context.findJob(idPrefix: idString) {
            if let updated = try await context.changePriority(id: job.id, newPriority: priority) {
                return .success("Updated priority for '\(updated.title)' to \(priority)")
            }
        } else if let uuid = UUID(uuidString: idString) {
            if let updated = try await context.changePriority(id: uuid, newPriority: priority) {
                return .success("Updated priority for '\(updated.title)' to \(priority)")
            }
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// List all jobs
public struct ListJobsTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_list"
    public let name = "List Jobs"
    public let description = "List all jobs in the queue sorted by priority"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let jobs = try await context.listJobs()
        if jobs.isEmpty {
            return .success("Queue is empty")
        }

        let list = jobs.map { $0.formatted }.joined(separator: "\n")
        return .success("Jobs (\(jobs.count)):\n\(list)")
    }
}

/// Update job status
public struct UpdateJobStatusTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_status"
    public let name = "Update Status"
    public let description =
        "Update the status of a job (pending, in_progress, completed, cancelled)"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
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
        if let job = try await context.findJob(idPrefix: idString) {
            if let updated = try await context.updateStatus(id: job.id, status: status) {
                return .success("Updated '\(updated.title)' status to \(status.rawValue)")
            }
        } else if let uuid = UUID(uuidString: idString) {
            if let updated = try await context.updateStatus(id: uuid, status: status) {
                return .success("Updated '\(updated.title)' status to \(status.rawValue)")
            }
        }

        return .failure("Job not found with ID: \(idString)")
    }
}

/// Clear all jobs
public struct ClearQueueTool: ContextTool, Sendable {
    public static let parentContextId = JobQueueContext.contextId

    public let id = "jq_clear"
    public let name = "Clear Queue"
    public let description = "Remove all jobs from the queue"
    public let requiresPermission = false

    private let context: JobQueueContext

    public init(context: JobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let count = try await context.clearQueue()
        return .success("Cleared \(count) job\(count == 1 ? "" : "s") from queue")
    }
}