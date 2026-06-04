import Foundation

enum L10n {
    private static let bundle: Bundle = {
        let bundleName = "iCloudSyncWatch_iCloudSyncWatch.bundle"
        let releaseURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        let localReleaseURL = URL(fileURLWithPath: "/Users/mindivelabs/code/icloud-sync-watch/.build/arm64-apple-macosx/release/\(bundleName)")
        let localDebugURL = URL(fileURLWithPath: "/Users/mindivelabs/code/icloud-sync-watch/.build/arm64-apple-macosx/debug/\(bundleName)")

        if let releaseURL, let bundle = Bundle(url: releaseURL) {
            return bundle
        }

        if let bundle = Bundle(url: localReleaseURL) {
            return bundle
        }

        if let bundle = Bundle(url: localDebugURL) {
            return bundle
        }

        return .main
    }()

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
