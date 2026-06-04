import Foundation

enum SyncEventPhase: String, Codable {
    case started
    case completed
}

struct ParsedSyncEvent: Sendable {
    let action: SyncAction
    let phase: SyncEventPhase
    let primaryPath: String
    let secondaryPath: String?
    let fileSize: Int?
    let decodeReason: String?
    let triggerReason: String?
    let timestamp: Date

    var correlationKey: String {
        switch action {
        case .upload, .download, .deleteFile, .createDirectory, .deleteDirectory:
            return "\(action.rawValue)|\(primaryPath)"
        case .renameFile, .moveFile, .renameDirectory, .moveDirectory:
            return "\(action.rawValue)|\(primaryPath)|\(secondaryPath ?? "")"
        }
    }
}
