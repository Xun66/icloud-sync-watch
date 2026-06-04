import Foundation

struct AppStateRepository {
    let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> AppSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var snapshot = AppSnapshot.default

        for rawLine in content.split(whereSeparator: \.isNewline) {
            guard !rawLine.isEmpty else {
                continue
            }

            let lineData = Data(rawLine.utf8)
            let record = try decoder.decode(AppStateLogRecord.self, from: lineData)
            apply(record, to: &snapshot)
        }

        return snapshot
    }

    func appendKeepMonitoringWhileHidden(_ value: Bool) throws {
        try append(.settings(keepMonitoringWhileHidden: value))
    }

    func appendInsertedActivity(_ activity: ActivityEntry) throws {
        try append(.insertActivity(activity))
    }

    func appendUpdatedActivity(_ activity: ActivityEntry) throws {
        try append(.updateActivity(activity))
    }

    func appendInsertedPause(_ pause: PauseEntry) throws {
        try append(.insertPause(pause))
    }

    func compact(with snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let line = try encodeLine(.snapshot(snapshot))
        try line.write(to: fileURL, options: .atomic)
    }

    private func append(_ record: AppStateLogRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: encodeLine(record))
    }

    private func encodeLine(_ record: AppStateLogRecord) throws -> Data {
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    private func apply(_ record: AppStateLogRecord, to snapshot: inout AppSnapshot) {
        switch record.kind {
        case .snapshot:
            snapshot = record.snapshot ?? .default
        case .settings:
            if let keepMonitoringWhileHidden = record.keepMonitoringWhileHidden {
                snapshot.keepMonitoringWhileHidden = keepMonitoringWhileHidden
            }
        case .insertActivity:
            guard let activity = record.activity else {
                return
            }
            snapshot.entries.removeAll { $0.id == activity.id }
            snapshot.entries.insert(.activity(activity), at: 0)
        case .updateActivity:
            guard let activity = record.activity else {
                return
            }
            if let index = snapshot.entries.firstIndex(where: { $0.id == activity.id }) {
                snapshot.entries[index] = .activity(activity)
            } else {
                snapshot.entries.insert(.activity(activity), at: 0)
            }
        case .insertPause:
            guard let pause = record.pause else {
                return
            }
            snapshot.entries.removeAll { $0.id == pause.id }
            snapshot.entries.insert(.pause(pause), at: 0)
        }
    }
}

private struct AppStateLogRecord: Codable {
    enum Kind: String, Codable {
        case snapshot
        case settings
        case insertActivity
        case updateActivity
        case insertPause
    }

    let kind: Kind
    let snapshot: AppSnapshot?
    let keepMonitoringWhileHidden: Bool?
    let activity: ActivityEntry?
    let pause: PauseEntry?

    static func snapshot(_ snapshot: AppSnapshot) -> AppStateLogRecord {
        AppStateLogRecord(
            kind: .snapshot,
            snapshot: snapshot,
            keepMonitoringWhileHidden: nil,
            activity: nil,
            pause: nil
        )
    }

    static func settings(keepMonitoringWhileHidden: Bool) -> AppStateLogRecord {
        AppStateLogRecord(
            kind: .settings,
            snapshot: nil,
            keepMonitoringWhileHidden: keepMonitoringWhileHidden,
            activity: nil,
            pause: nil
        )
    }

    static func insertActivity(_ activity: ActivityEntry) -> AppStateLogRecord {
        AppStateLogRecord(
            kind: .insertActivity,
            snapshot: nil,
            keepMonitoringWhileHidden: nil,
            activity: activity,
            pause: nil
        )
    }

    static func updateActivity(_ activity: ActivityEntry) -> AppStateLogRecord {
        AppStateLogRecord(
            kind: .updateActivity,
            snapshot: nil,
            keepMonitoringWhileHidden: nil,
            activity: activity,
            pause: nil
        )
    }

    static func insertPause(_ pause: PauseEntry) -> AppStateLogRecord {
        AppStateLogRecord(
            kind: .insertPause,
            snapshot: nil,
            keepMonitoringWhileHidden: nil,
            activity: nil,
            pause: pause
        )
    }
}
