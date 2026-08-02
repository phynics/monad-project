import Foundation
import PKShared

public struct ChatRequest: Codable, Sendable {
    public let message: String
    public let toolOutputs: [ToolOutputSubmission]?
    public let requestOriginId: UUID?
    public let attachedTools: [ToolReference]?

    public init(
        message: String,
        toolOutputs: [ToolOutputSubmission]? = nil,
        requestOriginId: UUID? = nil,
        attachedTools: [ToolReference]? = nil
    ) {
        self.message = message
        self.toolOutputs = toolOutputs
        self.requestOriginId = requestOriginId
        self.attachedTools = attachedTools
    }
}

public struct ChatResponse: Codable, Sendable {
    public let response: String

    public init(response: String) {
        self.response = response
    }
}

/// Availability metadata for one completed-turn inspection artifact.
///
/// Monad deliberately returns this instead of a partial or reconstructed artifact when
/// the artifact was not captured during prompt composition. Clients can treat
/// `.permanentlyUnavailable` as a stable terminal state rather than a retryable error.
public struct TurnInspectionArtifactAvailability: Codable, Sendable, Equatable {
    public let availability: Availability
    public let reason: Reason

    public init(availability: Availability, reason: Reason) {
        self.availability = availability
        self.reason = reason
    }

    public enum Availability: String, Codable, Sendable {
        case permanentlyUnavailable
    }

    public enum Reason: String, Codable, Sendable {
        case notCapturedByMonad
    }
}

/// Monad's completed-turn prompt inspection contract.
///
/// Prompt sections, the exact provider payload, and prompt-journal diffs exist only in
/// PositronicKit's optional compose-time inspection hook. Monad does not install that
/// hook or persist its data, so this response explicitly reports each artifact as
/// permanently unavailable rather than presenting fabricated or lossy data.
public struct TurnInspectionAvailabilityResponse: Codable, Sendable, Equatable {
    public let timelineId: UUID
    public let inspectionScope: InspectionScope
    public let promptSectionTree: TurnInspectionArtifactAvailability
    public let sentProviderPayload: TurnInspectionArtifactAvailability
    public let journalDiffs: TurnInspectionArtifactAvailability

    public init(timelineId: UUID) {
        self.timelineId = timelineId
        inspectionScope = .completedTurns
        let unavailable = TurnInspectionArtifactAvailability(
            availability: .permanentlyUnavailable,
            reason: .notCapturedByMonad
        )
        promptSectionTree = unavailable
        sentProviderPayload = unavailable
        journalDiffs = unavailable
    }

    public enum InspectionScope: String, Codable, Sendable {
        case completedTurns
    }
}
