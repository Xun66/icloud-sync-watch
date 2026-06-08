import Foundation
import Testing
@testable import iCloudSyncWatch

struct AppStateRepositoryTests {
    @Test
    func replaysJsonlDeltaRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppStateRepository(fileURL: directory.appendingPathComponent("state.jsonl"))

        let first = ActivityEntry(
            id: UUID(),
            correlationKey: "download|/tmp/a",
            action: .download,
            status: .running,
            primaryPath: "/tmp/a.txt",
            secondaryPath: nil,
            fileSize: 10,
            decodeReason: nil,
            triggerDiffs: [],
            triggerWhy: ["itemChangedRemotely"],
            startedAt: .now,
            finishedAt: nil,
            durationSeconds: nil,
            lastUpdatedAt: .now
        )

        var updatedFirst = first
        updatedFirst.status = .completed
        updatedFirst.durationSeconds = 1.5
        updatedFirst.finishedAt = Date(timeIntervalSinceNow: 1)

        let second = ActivityEntry(
            id: UUID(),
            correlationKey: "upload|/tmp/b",
            action: .upload,
            status: .running,
            primaryPath: "/tmp/b.txt",
            secondaryPath: nil,
            fileSize: 20,
            decodeReason: nil,
            triggerDiffs: ["content", "mtime"],
            triggerWhy: [],
            startedAt: .now,
            finishedAt: nil,
            durationSeconds: nil,
            lastUpdatedAt: .now
        )

        try repository.appendKeepMonitoringWhileHidden(false)
        try repository.appendInsertedActivity(first)
        try repository.appendUpdatedActivity(updatedFirst)
        try repository.appendInsertedActivity(second)

        let loaded = try repository.load()

        #expect(loaded.keepMonitoringWhileHidden == false)
        #expect(loaded.entries.count == 2)
        #expect(loaded.entries[0].activity?.id == second.id)
        #expect(loaded.entries[1].activity?.id == first.id)
        #expect(loaded.entries[1].activity?.status == .completed)
        #expect(loaded.entries[1].activity?.durationSeconds == 1.5)
    }

    @Test
    func reportsIncompatibleStateFileWithPathAndLineNumber() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("state.jsonl")
        let repository = AppStateRepository(fileURL: fileURL)

        let legacyLine = """
        {"kind":"insertActivity","snapshot":null,"keepMonitoringWhileHidden":null,"activity":{"id":"00000000-0000-0000-0000-000000000001","correlationKey":"upload|/tmp/a","action":"upload","status":"running","primaryPath":"/tmp/a","secondaryPath":null,"fileSize":12,"decodeReason":null,"triggerReason":"content|mtime","startedAt":"2026-06-08T12:00:00Z","finishedAt":null,"durationSeconds":null,"lastUpdatedAt":"2026-06-08T12:00:00Z"},"pause":null}
        """
        try legacyLine.write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            _ = try repository.load()
            Issue.record("expected incompatible state file error")
        } catch {
            let message = error.localizedDescription
            #expect(message.contains(fileURL.path))
            #expect(message.contains("line 1"))
            #expect(message.contains("triggerDiffs"))
        }
    }
}
