import Foundation
import MonadShared
import Logging

// MARK: - BackgroundJobQueueContext

/// A ToolContext that provides job queue management capabilities.
///
/// When activated via the gateway tool, this context exposes tools
/// for adding, removing, prioritizing, and managing jobs in a queue.
public actor BackgroundJobQueueContext: ToolContext {
    public static let contextId = "job_queue"
    public static let displayName = "BackgroundJob Queue Manager"
    public static let contextDescription = "Manage a queue of jobs with priorities and statuses"

    private let logger = Logger.module(named: "tools")
    private let backgroundJobStore: any BackgroundJobStoreProtocol
    private let timelineId: UUID

    public var contextTools: [AnyTool] {
        [
            AnyTool(AddJobTool(context: self)),
            AnyTool(RemoveJobTool(context: self)),
            AnyTool(ChangePriorityTool(context: self)),
            AnyTool(ListJobsTool(context: self)),
            AnyTool(UpdateJobStatusTool(context: self)),
            AnyTool(ClearQueueTool(context: self))
        ]
    }

    public init(backgroundJobStore: any BackgroundJobStoreProtocol, timelineId: UUID) {
        self.backgroundJobStore = backgroundJobStore
        self.timelineId = timelineId
    }

    public func activate() async {
        logger.info("BackgroundJob Queue context activated")
    }

    public func deactivate() async {
        logger.info("BackgroundJob Queue context deactivated")
    }

    public func formatState() async -> String {
        guard let jobs = try? await backgroundJobStore.fetchJobs(for: timelineId) else {
            return "**BackgroundJob Queue**: Error fetching jobs"
        }

        if jobs.isEmpty {
            return "**BackgroundJob Queue**: Empty"
        }

        let sortedJobs = jobs.sorted { $0.priority > $1.priority }
        let jobList = sortedJobs.map { $0.formatted }.joined(separator: "\n")

        return """
            **BackgroundJob Queue** (\(jobs.count) job\(jobs.count == 1 ? "" : "s")):
            \(jobList)
            """
    }

    public func welcomeMessage() async -> String {
        let toolList = contextTools.map { "- `\($0.id)`: \($0.description)" }.joined(
            separator: "\n")
        return """
            ## BackgroundJob Queue Manager Activated

            You are now in job queue management mode. Available commands:

            \(toolList)

            > **Note**: Calling any tool outside this context will exit job queue mode.

            \(await formatState())
            """
    }

    // MARK: - Queue Operations

    public func addJob(title: String, description: String?, priority: Int) async throws -> BackgroundJob {
        let job = BackgroundJob(timelineId: timelineId, title: title, description: description, priority: priority)
        try await backgroundJobStore.saveJob(job)
        logger.info("Added job: \(job.id)")
        return job
    }

    public func launchSubagent(request: AddBackgroundJobRequest) async throws -> BackgroundJob {
        let job = BackgroundJob(
            timelineId: timelineId,
            parentId: request.parentId,
            title: request.title,
            description: request.description,
            priority: request.priority,
            agentId: request.agentId ?? "default"
        )
        try await backgroundJobStore.saveJob(job)
        logger.info("Launched subagent job: \(job.id) (agent: \(job.agentId))")
        return job
    }

    public func removeJob(id: UUID) async throws -> BackgroundJob? {
        if let job = try await backgroundJobStore.fetchJob(id: id) {
            try await backgroundJobStore.deleteJob(id: id)
            logger.info("Removed job: \(id)")
            return job
        }
        return nil
    }

    public func changePriority(id: UUID, newPriority: Int) async throws -> BackgroundJob? {
        if var job = try await backgroundJobStore.fetchJob(id: id) {
            job.priority = newPriority
            job.updatedAt = Date()
            try await backgroundJobStore.saveJob(job)
            logger.info("Changed priority for job: \(id) to \(newPriority)")
            return job
        }
        return nil
    }

    public func updateStatus(id: UUID, status: BackgroundJob.Status) async throws -> BackgroundJob? {
        if var job = try await backgroundJobStore.fetchJob(id: id) {
            job.status = status
            job.updatedAt = Date()
            try await backgroundJobStore.saveJob(job)
            logger.info("Updated status for job: \(id) to \(status.rawValue)")
            return job
        }
        return nil
    }

    public func listJobs() async throws -> [BackgroundJob] {
        return try await backgroundJobStore.fetchJobs(for: timelineId).sorted { $0.priority > $1.priority }
    }

    public func clearQueue() async throws -> Int {
        let jobs = try await backgroundJobStore.fetchJobs(for: timelineId)
        for job in jobs {
            try await backgroundJobStore.deleteJob(id: job.id)
        }
        logger.info("Cleared \(jobs.count) jobs from queue")
        return jobs.count
    }

    public func getJob(id: UUID) async throws -> BackgroundJob? {
        try await backgroundJobStore.fetchJob(id: id)
    }

    public func findJob(idPrefix: String) async throws -> BackgroundJob? {
        let jobs = try await backgroundJobStore.fetchJobs(for: timelineId)
        return jobs.first { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }
    }

    /// Dequeue the next pending job with highest priority.
    /// Marks the job as in_progress and returns it for processing.
    /// Returns nil if no pending jobs are available.
    public func dequeueNext() async throws -> BackgroundJob? {
        let jobs = try await backgroundJobStore.fetchJobs(for: timelineId)

        // Find highest priority pending job
        let pending = jobs.filter { $0.status == .pending }
            .sorted { $0.priority > $1.priority }

        guard var nextJob = pending.first else {
            return nil
        }

        // Mark as in progress
        nextJob.status = .inProgress
        nextJob.updatedAt = Date()
        try await backgroundJobStore.saveJob(nextJob)

        logger.info("Dequeued job: \(nextJob.title) (priority: \(nextJob.priority))")
        return nextJob
    }

    /// Check if there are pending jobs that can be dequeued
    public func hasPendingJobs() async throws -> Bool {
        let jobs = try await backgroundJobStore.fetchJobs(for: timelineId)
        return jobs.contains { $0.status == .pending }
    }

    public func formatPinnedState() async -> String? {
        nil
    }
}

// MARK: - Context Tools

/// Add a new job to the queue
public struct AddJobTool: ContextTool, Sendable {
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_add"
    public let name = "Add BackgroundJob"
    public let description = "Add a new job to the queue"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { b in
            b.string("title", description: "BackgroundJob title", required: true)
            b.string("description", description: "BackgroundJob description")
            b.integer("priority", description: "Priority level (higher = more important, default: 0)")
        }.schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let title: String
        do {
            title = try params.require("title", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let description = params.optional("description", as: String.self)
        let priority = params.optional("priority", as: Int.self) ?? 0

        let job = try await context.addJob(title: title, description: description, priority: priority)
        return .success("Added job: \(job.title) [ID: \(job.id.uuidString.prefix(8))]")
    }
}

/// Remove a job from the queue
public struct RemoveJobTool: ContextTool, Sendable {
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_remove"
    public let name = "Remove BackgroundJob"
    public let description = "Remove a job from the queue by ID"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { b in
            b.string("id", description: "BackgroundJob ID (full or prefix)", required: true)
        }.schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let idString: String
        do {
            idString = try params.require("id", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        // Try to find by prefix first, then by full UUID
        if let job = try await context.findJob(idPrefix: idString) {
            _ = try await context.removeJob(id: job.id)
            return .success("Removed job: \(job.title)")
        } else if let uuid = UUID(uuidString: idString),
            let job = try await context.removeJob(id: uuid) {
            return .success("Removed job: \(job.title)")
        }

        return .failure("BackgroundJob not found with ID: \(idString)")
    }
}

/// Change job priority
public struct ChangePriorityTool: ContextTool, Sendable {
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_priority"
    public let name = "Change Priority"
    public let description = "Change the priority of a job"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { b in
            b.string("id", description: "BackgroundJob ID (full or prefix)", required: true)
            b.integer("priority", description: "New priority level", required: true)
        }.schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let idString: String
        let priority: Int
        do {
            idString = try params.require("id", as: String.self)
            priority = try params.require("priority", as: Int.self)
        } catch {
            return .failure(error.localizedDescription)
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

        return .failure("BackgroundJob not found with ID: \(idString)")
    }
}

/// List all jobs
public struct ListJobsTool: ContextTool, Sendable {
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_list"
    public let name = "List Jobs"
    public let description = "List all jobs in the queue sorted by priority"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { _ in }.schema
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
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_status"
    public let name = "Update Status"
    public let description =
        "Update the status of a job (pending, in_progress, completed, cancelled)"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { b in
            b.string("id", description: "BackgroundJob ID (full or prefix)", required: true)
            b.stringEnum("status", description: "New status", values: ["pending", "in_progress", "completed", "cancelled"], required: true)
        }.schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let idString: String
        let statusString: String
        do {
            idString = try params.require("id", as: String.self)
            statusString = try params.require("status", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        guard let status = BackgroundJob.Status(rawValue: statusString) else {
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

        return .failure("BackgroundJob not found with ID: \(idString)")
    }
}

/// Clear all jobs
public struct ClearQueueTool: ContextTool, Sendable {
    public static let parentContextId = BackgroundJobQueueContext.contextId

    public let id = "jq_clear"
    public let name = "Clear Queue"
    public let description = "Remove all jobs from the queue"
    public let requiresPermission = false

    private let context: BackgroundJobQueueContext

    public init(context: BackgroundJobQueueContext) {
        self.context = context
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { _ in }.schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let count = try await context.clearQueue()
        return .success("Cleared \(count) job\(count == 1 ? "" : "s") from queue")
    }
}
