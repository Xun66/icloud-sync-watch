import Foundation

enum DateFormatting {
    static func pauseDescription(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 3
        return formatter.string(from: interval) ?? "0m"
    }

    static func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func durationText(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "-- s"
        }
        return String(format: "%.1fs", duration)
    }

    static func fileSizeText(_ bytes: Int?) -> String {
        guard let bytes else {
            return "--"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
