import Foundation
import Testing
@testable import iCloudSyncWatch

@MainActor
struct ActivityStoreTests {
    @Test
    func insertsPauseDividerAfterResumingFromHiddenState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))
        try repository.compact(with:
            AppSnapshot(
                keepMonitoringWhileHidden: false,
                entries: []
            )
        )

        let monitor = FakeMonitor()
        let store = try ActivityStore(repository: repository, monitor: monitor)

        store.setInterfaceVisible(false)
        store.setInterfaceVisible(true)

        #expect(monitor.startCount == 1)
        #expect(monitor.stopCount == 1)
        #expect(store.snapshot.entries.count == 1)
        #expect(store.snapshot.entries.first?.kind == .pause)
    }

    @Test
    func firstOpenUsesLaunchTimeAsPauseStart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))
        try repository.compact(with: AppSnapshot(keepMonitoringWhileHidden: false, entries: []))

        let monitor = FakeMonitor()
        let store = try ActivityStore(repository: repository, monitor: monitor)

        Thread.sleep(forTimeInterval: 0.02)
        store.setInterfaceVisible(true)

        let pauseEntry = try #require(store.snapshot.entries.first?.pause)
        #expect(pauseEntry.duration > 0.01)
    }

    @Test
    func replacesLeadingPauseDividerInsteadOfStacking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))
        try repository.compact(with: AppSnapshot(keepMonitoringWhileHidden: false, entries: []))

        let monitor = FakeMonitor()
        let store = try ActivityStore(repository: repository, monitor: monitor)

        store.setInterfaceVisible(true)
        store.setInterfaceVisible(false)
        Thread.sleep(forTimeInterval: 0.02)
        store.setInterfaceVisible(true)

        let pauseEntries = store.snapshot.entries.compactMap(\.pause)
        #expect(pauseEntries.count == 1)
        #expect(pauseEntries[0].duration > 0.01)
    }

    @Test
    func doesNotShowErrorWhenStoppingMonitoring() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))
        try repository.compact(with: AppSnapshot(keepMonitoringWhileHidden: false, entries: []))

        let monitor = FakeMonitor()
        let store = try ActivityStore(repository: repository, monitor: monitor)

        store.setInterfaceVisible(true)
        monitor.onFailure?("should not appear for a normal stop")
        store.dismissError()
        store.setInterfaceVisible(false)

        #expect(store.lastErrorMessage == nil)
    }

    @Test
    func clearEntriesRemovesVisibleEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))

        let entry = ActivityEntry(
            id: UUID(),
            correlationKey: "upload|/tmp/a",
            action: .upload,
            status: .completed,
            primaryPath: "/tmp/a",
            secondaryPath: nil,
            fileSize: 12,
            decodeReason: nil,
            triggerDiffs: ["content"],
            triggerWhy: ["itemChangedRemotely"],
            startedAt: .now,
            finishedAt: .now,
            durationSeconds: 0.5,
            lastUpdatedAt: .now
        )
        try repository.compact(with: AppSnapshot(keepMonitoringWhileHidden: false, entries: [.activity(entry)]))

        let monitor = FakeMonitor()
        let store = try ActivityStore(repository: repository, monitor: monitor)

        #expect(store.visibleEntries.count == 1)
        store.clearEntries()
        #expect(store.visibleEntries.isEmpty)
    }
}

private final class FakeMonitor: LogStreamControlling {
    var onEvents: (([ParsedSyncEvent]) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}
