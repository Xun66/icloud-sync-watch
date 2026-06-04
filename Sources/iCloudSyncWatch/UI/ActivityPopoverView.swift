import AppKit
import QuartzCore
import SwiftUI

struct ActivityPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: ActivityStore

    @State private var expandedEntryIDs: Set<UUID> = []

    private var menuActions: AppMenuActions {
        AppMenuActions(store: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let errorMessage = store.lastErrorMessage {
                ErrorBanner(message: errorMessage) {
                    store.dismissError()
                }
            }
            Divider()
            content
        }
        .frame(width: 320, height: 500)
        .background(containerBackgroundColor)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppPaths.appName)
                    .font(.system(size: 15, weight: .semibold))
                Text(store.keepMonitoringWhileHidden ? L10n.tr("header.watchEnabled") : L10n.tr("header.watchDisabled"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsMenu
                .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(headerBackgroundColor)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(L10n.tr("menu.keepMonitoring"), isOn: Binding(
                get: { store.keepMonitoringWhileHidden },
                set: { store.setKeepMonitoringWhileHidden($0) }
            ))
            Menu(L10n.tr("menu.help")) {
                Button(L10n.tr("menu.help.incomplete")) {
                    menuActions.showIncompleteChangesHelp()
                }
                Button(L10n.tr("menu.help.privacy")) {
                    menuActions.showPrivacyAccessHelp()
                }
            }
            Button(L10n.tr("menu.feedback")) {
                menuActions.sendFeedback()
            }
            Button(L10n.tr("menu.about")) {
                menuActions.showAbout()
            }
            Divider()
            Button(L10n.tr("menu.quit")) {
                menuActions.quit()
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.visibleEntries.isEmpty {
                    emptyState
                } else {
                    ForEach(store.visibleEntries) { entry in
                        switch entry.kind {
                        case .activity:
                            if let activity = entry.activity {
                                ActivityRowView(
                                    activity: activity,
                                    isExpanded: expandedEntryIDs.contains(activity.id),
                                    toggleExpanded: { toggleExpanded(activity.id) },
                                    openParentDirectory: { openDirectory(path: activity.parentDirectoryPath) }
                                )
                            }
                        case .pause:
                            if let pause = entry.pause {
                                PauseDividerRowView(entry: pause)
                            }
                        }
                    }
                }

                recordFileLink
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(contentBackgroundColor)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(L10n.tr("empty.none"))
                .font(.system(size: 12, weight: .medium))
            Text(store.keepMonitoringWhileHidden ? L10n.tr("empty.monitoring.enabled") : L10n.tr("empty.monitoring.disabled"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var recordFileLink: some View {
        HStack {
            Spacer(minLength: 0)
            Button(L10n.tr("record.view")) {
                store.revealSnapshotFileInFinder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedEntryIDs.contains(id) {
            expandedEntryIDs.remove(id)
        } else {
            expandedEntryIDs.insert(id)
        }
    }

    private func openDirectory(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private var containerBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 1))
        }
        return .white
    }

    private var contentBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
        }
        return .white
    }

    private var headerBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1))
        }
        return Color(red: 247 / 255, green: 245 / 255, blue: 242 / 255)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

private struct ActivityRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let activity: ActivityEntry
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let openParentDirectory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ActivityGlyphView(
                    symbolName: activity.action.symbolName,
                    tint: iconColor,
                    spinning: activity.status == .running
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(action: openParentDirectory) {
                        Text(activity.parentDirectoryName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(DateFormatting.relativeTimestamp(activity.lastUpdatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let decodeReason = activity.decodeReason {
                            WarningIconView(message: L10n.tr("tooltip.decodeFailure", decodeReason))
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            if isExpanded {
                Divider()
                    .padding(.leading, 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(activity.action.detailTitle)
                        Text(L10n.tr("detail.duration", DateFormatting.durationText(activity.durationSeconds)))
                        Text(DateFormatting.fileSizeText(activity.fileSize))
                    }

                    HStack(alignment: .top, spacing: 4) {
                        Text(L10n.tr("detail.triggerReasonLabel"))
                        Text(activity.triggerReason ?? L10n.tr("detail.unknownChange"))
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 34)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
            }
        }
        .background(currentBackgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpanded)
        .onHover { hovered in
            isHovered = hovered
        }
    }

    private var iconColor: Color {
        switch activity.action {
        case .upload:
            .orange
        case .download:
            .blue
        case .deleteFile, .deleteDirectory:
            .red
        case .createDirectory:
            .green
        case .renameFile, .moveFile, .renameDirectory, .moveDirectory:
            .accentColor
        }
    }

    private var rowBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
        }
        return .white
    }

    private var hoverBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.30, alpha: 1))
        }
        return Color(nsColor: NSColor(calibratedRed: 0.92, green: 0.96, blue: 1.0, alpha: 1))
    }

    private var currentBackgroundColor: Color {
        isHovered ? hoverBackgroundColor : rowBackgroundColor
    }
}

private struct WarningIconView: View {
    let message: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.yellow)
            .frame(width: 12, height: 12)
            .contentShape(Rectangle())
            .help(message)
            .accessibilityLabel(message)
    }
}

private struct ActivityGlyphView: View {
    let symbolName: String
    let tint: Color
    let spinning: Bool

    var body: some View {
        ZStack {
            if spinning {
                DashedSpinnerView(color: NSColor(tint), lineWidth: 1.8)
                    .frame(width: 20, height: 20)
            }

            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 18, height: 18)

            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 20, height: 20)
    }
}

private struct PauseDividerRowView: View {
    let entry: PauseEntry

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text(L10n.tr("monitor.paused", DateFormatting.pauseDescription(from: entry.duration)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
    }
}

private struct DashedSpinnerView: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> SpinnerHostView {
        let view = SpinnerHostView()
        view.update(color: color, lineWidth: lineWidth)
        return view
    }

    func updateNSView(_ nsView: SpinnerHostView, context: Context) {
        nsView.update(color: color, lineWidth: lineWidth)
    }
}

private final class SpinnerHostView: NSView {
    private let shapeLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        let inset = max(1.0, shapeLayer.lineWidth / 2)
        shapeLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: inset, dy: inset),
            transform: nil
        )
    }

    func update(color: NSColor, lineWidth: CGFloat) {
        shapeLayer.fillColor = NSColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.lineDashPattern = [3, 2]
        shapeLayer.lineCap = .round

        if shapeLayer.animation(forKey: "rotation") == nil {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = Double.pi * 2
            animation.duration = 1.6
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            shapeLayer.add(animation, forKey: "rotation")
        }

        needsLayout = true
    }
}
