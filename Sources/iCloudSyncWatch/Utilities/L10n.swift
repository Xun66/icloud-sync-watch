import Foundation

enum L10n {
    private static let bundle: Bundle = {
        let bundleName = "iCloudSyncWatch_iCloudSyncWatch.bundle"
        let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else {
            Swift.fatalError("Could not load resource bundle at \(bundleURL?.path ?? "nil")")
        }
        return bundle
    }()

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
