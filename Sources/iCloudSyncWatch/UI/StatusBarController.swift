import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    var onVisibilityChanged: ((Bool) -> Void)?

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let menuActions: AppMenuActions
    private var cancellables: Set<AnyCancellable> = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(store: ActivityStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.menuActions = AppMenuActions(store: store)
        super.init()

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: ActivityPopoverView(store: store)
        )

        store.$statusItemBadgeState
            .sink { [weak self] badgeState in
                self?.updateStatusItemImage(badgeState: badgeState)
            }
            .store(in: &cancellables)

        if let button = statusItem.button {
            button.image = makeStatusItemImage(badgeState: store.statusItemBadgeState)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if NSApp.currentEvent?.type == .rightMouseUp {
            if popover.isShown {
                popover.performClose(nil)
            }
            statusItem.menu = menuActions.makeStatusItemMenu()
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installPopoverDismissMonitors()
            onVisibilityChanged?(true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitors()
        onVisibilityChanged?(false)
    }

    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfShown()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldClosePopover(for: event) {
                self.closePopoverIfShown()
            }

            return event
        }
    }

    private func removePopoverDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else {
            return false
        }

        let popoverWindow = popover.contentViewController?.view.window
        let statusWindow = statusItem.button?.window
        return event.window !== popoverWindow && event.window !== statusWindow
    }

    private func closePopoverIfShown() {
        guard popover.isShown else {
            return
        }
        popover.performClose(nil)
    }

    private func updateStatusItemImage(badgeState: StatusItemBadgeState) {
        statusItem.button?.image = makeStatusItemImage(badgeState: badgeState)
    }

    private func makeStatusItemImage(badgeState: StatusItemBadgeState) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let image = NSImage(
            systemSymbolName: "icloud",
            accessibilityDescription: AppPaths.appName
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
