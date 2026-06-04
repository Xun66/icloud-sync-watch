import AppKit
import Foundation

@MainActor
final class MainApplication: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var activityStore: ActivityStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let repository = AppStateRepository(fileURL: try AppPaths.snapshotFileURL())
            let resolver = try PathResolver(volumePath: FileManager.default.homeDirectoryForCurrentUser)
            let parser = LiveLogParser(resolver: resolver)
            let monitor = UnifiedLogStreamService(parser: parser)
            let store = try ActivityStore(repository: repository, monitor: monitor)
            let controller = StatusBarController(store: store)
            controller.onVisibilityChanged = { [weak store] visible in
                store?.setInterfaceVisible(visible)
            }

            self.activityStore = store
            self.statusBarController = controller
        } catch {
            showFatalErrorAndTerminate(message: error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityStore?.setInterfaceVisible(false)
    }

    private func showFatalErrorAndTerminate(message: String) {
        fputs(L10n.tr("error.launchFailedText", message) + "\n", stderr)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.tr("error.launchFailedTitle")
        alert.informativeText = message
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
