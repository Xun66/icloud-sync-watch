import Foundation

enum TimelineEntryKind: String, Codable {
    case activity
    case pause
}

enum TimelineEntryStatus: String, Codable {
    case running
    case completed
}

struct ActivityEntry: Identifiable, Codable {
    let id: UUID
    let correlationKey: String
    var action: SyncAction
    var status: TimelineEntryStatus
    var primaryPath: String
    var secondaryPath: String?
    var fileSize: Int?
    var decodeReason: String?
    var triggerDiffs: [String]
    var triggerWhy: [String]
    var startedAt: Date
    var finishedAt: Date?
    var durationSeconds: TimeInterval?
    var lastUpdatedAt: Date

    var displayName: String {
        URL(fileURLWithPath: displayPath).lastPathComponent
    }

    var displayPath: String {
        secondaryPath ?? primaryPath
    }

    var parentDirectoryPath: String {
        URL(fileURLWithPath: displayPath).deletingLastPathComponent().path
    }

    var parentDirectoryName: String {
        let parentURL = URL(fileURLWithPath: parentDirectoryPath)
        let name = parentURL.lastPathComponent
        return name.isEmpty ? parentDirectoryPath : name
    }
}

struct PauseEntry: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

struct TimelineEntry: Identifiable, Codable {
    let id: UUID
    let kind: TimelineEntryKind
    var activity: ActivityEntry?
    var pause: PauseEntry?
    var sortDate: Date

    static func activity(_ value: ActivityEntry) -> TimelineEntry {
        TimelineEntry(
            id: value.id,
            kind: .activity,
            activity: value,
            pause: nil,
            sortDate: value.lastUpdatedAt
        )
    }

    static func pause(_ value: PauseEntry) -> TimelineEntry {
        TimelineEntry(
            id: value.id,
            kind: .pause,
            activity: nil,
            pause: value,
            sortDate: value.endedAt
        )
    }
}
