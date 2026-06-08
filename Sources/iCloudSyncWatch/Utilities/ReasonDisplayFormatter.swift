import Foundation

enum ReasonDisplayFormatter {
    static func format(_ tokens: [String]) -> String {
        tokens.joined(separator: L10n.tr("detail.tokenSeparator"))
    }
}
