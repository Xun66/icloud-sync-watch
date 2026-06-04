import Foundation

struct AppSnapshot: Codable {
    var keepMonitoringWhileHidden: Bool
    var entries: [TimelineEntry]

    static let `default` = AppSnapshot(
        keepMonitoringWhileHidden: false,
        entries: []
    )
}
