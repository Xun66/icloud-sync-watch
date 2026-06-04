import AppKit

@MainActor
final class AppMenuActions {
    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
    }

    func toggleKeepMonitoring() {
        store.setKeepMonitoringWhileHidden(!store.keepMonitoringWhileHidden)
    }

    func showIncompleteChangesHelp() {
        InfoPanelPresenter.shared.show(.incompleteChanges)
    }

    func showPrivacyAccessHelp() {
        InfoPanelPresenter.shared.show(.privacyAccess)
    }

    func sendFeedback() {
        guard let url = URL(string: "https://github.com/Xun66/icloud-sync-watch/issues") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func showAbout() {
        InfoPanelPresenter.shared.show(.about)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func makeStatusItemMenu() -> NSMenu {
        let menu = NSMenu()

        let keepMonitoringItem = NSMenuItem(
            title: L10n.tr("menu.keepMonitoring"),
            action: #selector(handleToggleKeepMonitoring),
            keyEquivalent: ""
        )
        keepMonitoringItem.target = self
        keepMonitoringItem.state = store.keepMonitoringWhileHidden ? .on : .off
        menu.addItem(keepMonitoringItem)

        let helpItem = NSMenuItem(title: L10n.tr("menu.help"), action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: L10n.tr("menu.help"))

        let incompleteItem = NSMenuItem(
            title: L10n.tr("menu.help.incomplete"),
            action: #selector(handleShowIncompleteChangesHelp),
            keyEquivalent: ""
        )
        incompleteItem.target = self
        helpMenu.addItem(incompleteItem)

        let privacyItem = NSMenuItem(
            title: L10n.tr("menu.help.privacy"),
            action: #selector(handleShowPrivacyAccessHelp),
            keyEquivalent: ""
        )
        privacyItem.target = self
        helpMenu.addItem(privacyItem)

        menu.setSubmenu(helpMenu, for: helpItem)
        menu.addItem(helpItem)

        let feedbackItem = NSMenuItem(
            title: L10n.tr("menu.feedback"),
            action: #selector(handleSendFeedback),
            keyEquivalent: ""
        )
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        let aboutItem = NSMenuItem(
            title: L10n.tr("menu.about"),
            action: #selector(handleShowAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.tr("menu.quit"),
            action: #selector(handleQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func handleToggleKeepMonitoring() {
        toggleKeepMonitoring()
    }

    @objc
    private func handleShowIncompleteChangesHelp() {
        showIncompleteChangesHelp()
    }

    @objc
    private func handleShowPrivacyAccessHelp() {
        showPrivacyAccessHelp()
    }

    @objc
    private func handleSendFeedback() {
        sendFeedback()
    }

    @objc
    private func handleShowAbout() {
        showAbout()
    }

    @objc
    private func handleQuit() {
        quit()
    }
}
