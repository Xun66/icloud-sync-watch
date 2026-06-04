import AppKit
import SwiftUI

@MainActor
final class InfoPanelPresenter {
    static let shared = InfoPanelPresenter()

    private var controllers: [InfoPanelKind: NSWindowController] = [:]

    func show(_ kind: InfoPanelKind) {
        let controller: NSWindowController
        if let existing = controllers[kind] {
            controller = existing
        } else {
            let created = makeController(for: kind)
            controllers[kind] = created
            controller = created
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeController(for kind: InfoPanelKind) -> NSWindowController {
        let contentView = InfoPanelView(kind: kind)
        let hostingController = NSHostingController(rootView: contentView)
        let size = kind.windowSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.title = kind.title
        window.contentViewController = hostingController
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        return NSWindowController(window: window)
    }
}

enum InfoPanelKind: Hashable {
    case about
    case incompleteChanges
    case privacyAccess

    var title: String {
        switch self {
        case .about:
            return L10n.tr("about.title")
        case .incompleteChanges:
            return L10n.tr("help.incomplete.title")
        case .privacyAccess:
            return L10n.tr("help.privacy.title")
        }
    }

    var bodyText: String {
        switch self {
        case .about:
            return "\(L10n.tr("about.body"))\n\n\(L10n.tr("about.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))"
        case .incompleteChanges:
            return L10n.tr("help.incomplete.body")
        case .privacyAccess:
            return L10n.tr("help.privacy.body")
        }
    }

    var windowSize: NSSize {
        switch self {
        case .about:
            return NSSize(width: 520, height: 320)
        case .incompleteChanges, .privacyAccess:
            return NSSize(width: 440, height: 260)
        }
    }
}

private struct InfoPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: InfoPanelKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(kind.bodyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if kind == .about {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    LinkRow(
                        title: L10n.tr("about.sourceCode"),
                        destination: "https://github.com/Xun66/icloud-sync-watch"
                    )
                    LinkRow(
                        title: L10n.tr("about.issueTracker"),
                        destination: "https://github.com/Xun66/icloud-sync-watch/issues"
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backgroundColor)
    }

    private var iconName: String {
        switch kind {
        case .about:
            return "icloud"
        case .incompleteChanges:
            return "questionmark.bubble"
        case .privacyAccess:
            return "lock.shield"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .about:
            return .accentColor
        case .incompleteChanges:
            return .orange
        case .privacyAccess:
            return .blue
        }
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 1))
        }
        return Color(nsColor: NSColor.windowBackgroundColor)
    }
}

private struct LinkRow: View {
    let title: String
    let destination: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))

            Link(destination, destination: URL(string: destination)!)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
