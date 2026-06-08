import AppKit
import Combine
import Foundation

enum StatusItemBadgeState {
    case none
    case outlined
    case filled
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var statusItemBadgeState: StatusItemBadgeState = .none

    private let repository: AppStateRepository
    private let monitor: LogStreamControlling
    private var interfaceVisible = false
    private var pausedAt: Date?
    private var openEntryIDsByKey: [String: UUID] = [:]
    private let maxStoredEntries = 500
    private let compactThreshold = 200
    private var appendedRecordCount = 0

    init(repository: AppStateRepository, monitor: LogStreamControlling) throws {
        self.repository = repository
        self.monitor = monitor
        self.snapshot = try repository.load()
        self.pausedAt = snapshot.keepMonitoringWhileHidden ? nil : Date()

        for entry in snapshot.entries {
            guard entry.kind == .activity, let activity = entry.activity, activity.status == .running else {
                continue
            }
            openEntryIDsByKey[activity.correlationKey] = activity.id
        }

        monitor.onEvents = { [weak self] events in
            self?.apply(events: events)
        }
        monitor.onFailure = { [weak self] message in
            self?.lastErrorMessage = message
        }

        if snapshot.keepMonitoringWhileHidden {
            monitor.start()
        }
        updateStatusItemBadgeState()
    }

    var keepMonitoringWhileHidden: Bool {
        snapshot.keepMonitoringWhileHidden
    }

    var visibleEntries: [TimelineEntry] {
        snapshot.entries
    }

    func setInterfaceVisible(_ visible: Bool) {
        interfaceVisible = visible

        if visible {
            resumeMonitoringIfNeeded()
        } else if !snapshot.keepMonitoringWhileHidden {
            pausedAt = Date()
            monitor.stop()
        }
        updateStatusItemBadgeState()
    }

    func setKeepMonitoringWhileHidden(_ value: Bool) {
        snapshot.keepMonitoringWhileHidden = value
        persistKeepMonitoringWhileHidden(value)

        if value {
            resumeMonitoringIfNeeded()
        } else if !interfaceVisible {
            pausedAt = Date()
            monitor.stop()
        }
        updateStatusItemBadgeState()
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    var snapshotFileURL: URL {
        repository.fileURL
    }

    func revealEntryInFinder(path: String) {
        let target = FinderRevealTarget.resolve(path: path)

        switch target {
        case let .select(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case let .openDirectory(url):
            NSWorkspace.shared.open(url)
        }
    }

    func revealSnapshotFileInFinder() {
        do {
            if !FileManager.default.fileExists(atPath: repository.fileURL.path) {
                try repository.compact(with: snapshot)
                appendedRecordCount = 0
            }
            NSWorkspace.shared.activateFileViewerSelecting([repository.fileURL])
        } catch {
            lastErrorMessage = L10n.tr("error.createLogFile", error.localizedDescription)
        }
    }

    func clearEntries() {
        snapshot.entries.removeAll()
        openEntryIDsByKey.removeAll()
        compactSnapshot()
        updateStatusItemBadgeState()
    }

    private func resumeMonitoringIfNeeded() {
        if let pausedAt {
            let pauseEntry = PauseEntry(id: UUID(), startedAt: pausedAt, endedAt: Date())
            replaceLeadingPauseEntries(with: pauseEntry)
            self.pausedAt = nil
            compactSnapshot()
        }
        monitor.start()
        updateStatusItemBadgeState()
    }

    private func apply(events: [ParsedSyncEvent]) {
        for event in events {
            switch event.phase {
            case .started:
                applyStart(event)
            case .completed:
                applyCompletion(event)
            }
        }

        compactIfNeededAfterMutation()
        updateStatusItemBadgeState()
    }

    private func applyStart(_ event: ParsedSyncEvent) {
        if let existingID = openEntryIDsByKey[event.correlationKey],
           let index = snapshot.entries.firstIndex(where: { $0.id == existingID }),
           var activity = snapshot.entries[index].activity
        {
            activity.status = .running
            activity.fileSize = event.fileSize ?? activity.fileSize
            activity.decodeReason = event.decodeReason ?? activity.decodeReason
            if !event.triggerDiffs.isEmpty {
                activity.triggerDiffs = event.triggerDiffs
            }
            if !event.triggerWhy.isEmpty {
                activity.triggerWhy = event.triggerWhy
            }
            activity.lastUpdatedAt = event.timestamp
            snapshot.entries[index] = .activity(activity)
            persistUpdatedActivity(activity)
            return
        }

        let activity = ActivityEntry(
            id: UUID(),
            correlationKey: event.correlationKey,
            action: event.action,
            status: .running,
            primaryPath: event.primaryPath,
            secondaryPath: event.secondaryPath,
            fileSize: event.fileSize,
            decodeReason: event.decodeReason,
            triggerDiffs: event.triggerDiffs,
            triggerWhy: event.triggerWhy,
            startedAt: event.timestamp,
            finishedAt: nil,
            durationSeconds: nil,
            lastUpdatedAt: event.timestamp
        )
        openEntryIDsByKey[event.correlationKey] = activity.id
        snapshot.entries.insert(.activity(activity), at: 0)
        persistInsertedActivity(activity)
    }

    private func applyCompletion(_ event: ParsedSyncEvent) {
        if let existingID = openEntryIDsByKey.removeValue(forKey: event.correlationKey),
           let index = snapshot.entries.firstIndex(where: { $0.id == existingID }),
           var activity = snapshot.entries[index].activity
        {
            activity.status = .completed
            activity.secondaryPath = event.secondaryPath ?? activity.secondaryPath
            activity.fileSize = event.fileSize ?? activity.fileSize
            activity.decodeReason = event.decodeReason ?? activity.decodeReason
            if !event.triggerDiffs.isEmpty {
                activity.triggerDiffs = event.triggerDiffs
            }
            if !event.triggerWhy.isEmpty {
                activity.triggerWhy = event.triggerWhy
            }
            activity.finishedAt = event.timestamp
            activity.durationSeconds = event.timestamp.timeIntervalSince(activity.startedAt)
            activity.lastUpdatedAt = event.timestamp
            snapshot.entries[index] = .activity(activity)
            persistUpdatedActivity(activity)
            return
        }

        let activity = ActivityEntry(
            id: UUID(),
            correlationKey: event.correlationKey,
            action: event.action,
            status: .completed,
            primaryPath: event.primaryPath,
            secondaryPath: event.secondaryPath,
            fileSize: event.fileSize,
            decodeReason: event.decodeReason,
            triggerDiffs: event.triggerDiffs,
            triggerWhy: event.triggerWhy,
            startedAt: event.timestamp,
            finishedAt: event.timestamp,
            durationSeconds: nil,
            lastUpdatedAt: event.timestamp
        )
        snapshot.entries.insert(.activity(activity), at: 0)
        persistInsertedActivity(activity)
    }

    private func compactIfNeededAfterMutation() {
        let didTrim = trimEntriesIfNeeded()
        if didTrim || appendedRecordCount >= compactThreshold {
            compactSnapshot()
        }
    }

    private func trimEntriesIfNeeded() -> Bool {
        guard snapshot.entries.count > maxStoredEntries else {
            return false
        }

        snapshot.entries = Array(snapshot.entries.prefix(maxStoredEntries))
        let retainedIDs = Set(snapshot.entries.map(\.id))
        openEntryIDsByKey = openEntryIDsByKey.filter { retainedIDs.contains($0.value) }
        return true
    }

    private func persistKeepMonitoringWhileHidden(_ value: Bool) {
        do {
            try repository.appendKeepMonitoringWhileHidden(value)
            appendedRecordCount += 1
        } catch {
            lastErrorMessage = L10n.tr("error.saveState", error.localizedDescription)
        }
    }

    private func persistInsertedActivity(_ activity: ActivityEntry) {
        do {
            try repository.appendInsertedActivity(activity)
            appendedRecordCount += 1
        } catch {
            lastErrorMessage = L10n.tr("error.saveState", error.localizedDescription)
        }
    }

    private func persistUpdatedActivity(_ activity: ActivityEntry) {
        do {
            try repository.appendUpdatedActivity(activity)
            appendedRecordCount += 1
        } catch {
            lastErrorMessage = L10n.tr("error.saveState", error.localizedDescription)
        }
    }

    private func replaceLeadingPauseEntries(with pause: PauseEntry) {
        while snapshot.entries.first?.kind == .pause {
            snapshot.entries.removeFirst()
        }
        snapshot.entries.insert(.pause(pause), at: 0)
    }

    private func compactSnapshot() {
        do {
            try repository.compact(with: snapshot)
            appendedRecordCount = 0
        } catch {
            lastErrorMessage = L10n.tr("error.saveState", error.localizedDescription)
        }
    }

    private func updateStatusItemBadgeState() {
        guard snapshot.keepMonitoringWhileHidden else {
            statusItemBadgeState = .none
            return
        }
        let hasRunningActivity = snapshot.entries.contains { $0.activity?.status == .running }
        statusItemBadgeState = hasRunningActivity ? .filled : .outlined
    }
}
