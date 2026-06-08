import Foundation

enum FinderRevealTarget: Equatable {
    case select(URL)
    case openDirectory(URL)

    static func resolve(path: String, fileManager: FileManager = .default) -> FinderRevealTarget {
        let requestedURL = URL(fileURLWithPath: path)

        if fileManager.fileExists(atPath: requestedURL.path) {
            return .select(requestedURL)
        }

        var candidateURL = requestedURL.deletingLastPathComponent()
        while true {
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return .openDirectory(candidateURL)
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path {
                return .openDirectory(candidateURL)
            }
            candidateURL = parentURL
        }
    }
}
