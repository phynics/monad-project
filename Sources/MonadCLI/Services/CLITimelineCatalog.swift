import Foundation
import MonadShared
import PKShared

enum CLITimelinePeekResolution {
    case publicTimeline(TimelineResponse)
    case privateTimeline(UUID)
    case ambiguous([TimelineResponse])
    case privateTimelineUnavailable
    case notFound
}

struct CLITimelineCatalog {
    static func sortedPublicTimelines(_ timelines: [TimelineResponse]) -> [TimelineResponse] {
        timelines.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func resolvePeekTarget(
        query: String?,
        publicTimelines: [TimelineResponse],
        currentAgent: AgentInstance?
    ) -> CLITimelinePeekResolution {
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized?.isEmpty != false || normalized?.lowercased() == "private" {
            guard let currentAgent else { return .privateTimelineUnavailable }
            return .privateTimeline(currentAgent.privateTimelineId)
        }

        let timelines = sortedPublicTimelines(publicTimelines)
        guard let normalized else { return .notFound }

        if let index = Int(normalized), index > 0, index <= timelines.count {
            return .publicTimeline(timelines[index - 1])
        }

        let lowercasedQuery = normalized.lowercased()
        let exactTitleMatches = timelines.filter { ($0.title ?? "Untitled").lowercased() == lowercasedQuery }
        if exactTitleMatches.count == 1 {
            return .publicTimeline(exactTitleMatches[0])
        }
        if exactTitleMatches.count > 1 {
            return .ambiguous(exactTitleMatches)
        }

        let prefixTitleMatches = timelines.filter {
            ($0.title ?? "Untitled").lowercased().hasPrefix(lowercasedQuery)
        }
        if prefixTitleMatches.count == 1 {
            return .publicTimeline(prefixTitleMatches[0])
        }
        if prefixTitleMatches.count > 1 {
            return .ambiguous(prefixTitleMatches)
        }

        if let exactIDMatch = timelines.first(where: { $0.id.uuidString.lowercased() == lowercasedQuery }) {
            return .publicTimeline(exactIDMatch)
        }

        let prefixIDMatches = timelines.filter { $0.id.uuidString.lowercased().hasPrefix(lowercasedQuery) }
        if prefixIDMatches.count == 1 {
            return .publicTimeline(prefixIDMatches[0])
        }
        if prefixIDMatches.count > 1 {
            return .ambiguous(prefixIDMatches)
        }

        return .notFound
    }
}
