import Foundation

enum SyncAction: String, Codable, CaseIterable {
    case upload
    case download
    case deleteFile
    case createDirectory
    case deleteDirectory
    case renameFile
    case moveFile
    case renameDirectory
    case moveDirectory

    var displayTitle: String {
        switch self {
        case .upload:
            L10n.tr("action.upload")
        case .download:
            L10n.tr("action.download")
        case .deleteFile:
            L10n.tr("action.deleteFile")
        case .createDirectory:
            L10n.tr("action.createDirectory")
        case .deleteDirectory:
            L10n.tr("action.deleteDirectory")
        case .renameFile:
            L10n.tr("action.renameFile")
        case .moveFile:
            L10n.tr("action.moveFile")
        case .renameDirectory:
            L10n.tr("action.renameDirectory")
        case .moveDirectory:
            L10n.tr("action.moveDirectory")
        }
    }

    var detailTitle: String {
        switch self {
        case .upload:
            L10n.tr("detail.upload")
        case .download:
            L10n.tr("detail.download")
        case .deleteFile:
            L10n.tr("detail.deleteFile")
        case .createDirectory:
            L10n.tr("detail.createDirectory")
        case .deleteDirectory:
            L10n.tr("detail.deleteDirectory")
        case .renameFile:
            L10n.tr("detail.renameFile")
        case .moveFile:
            L10n.tr("detail.moveFile")
        case .renameDirectory:
            L10n.tr("detail.renameDirectory")
        case .moveDirectory:
            L10n.tr("detail.moveDirectory")
        }
    }

    var symbolName: String {
        switch self {
        case .upload:
            "arrow.up.circle.fill"
        case .download:
            "arrow.down.circle.fill"
        case .deleteFile:
            "trash.fill"
        case .createDirectory:
            "folder.badge.plus"
        case .deleteDirectory:
            "folder.badge.minus"
        case .renameFile, .renameDirectory:
            "pencil.circle.fill"
        case .moveFile, .moveDirectory:
            "arrowshape.right.circle.fill"
        }
    }
}
