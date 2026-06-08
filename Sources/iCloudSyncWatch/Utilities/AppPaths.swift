import Foundation

enum AppPaths {
    static let bundleIdentifier = "io.github.xun66.iCloudSyncWatch"
    static var appName: String { L10n.tr("app.name") }

    static func snapshotFileURL() throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("state.jsonl", isDirectory: false)
    }
}
