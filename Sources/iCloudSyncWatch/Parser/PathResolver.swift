import Darwin
import Foundation

protocol PathResolving: AnyObject {
    func localPath(for itemID: String) -> String?
    func localDirectoryPath(for fileID: String) -> String?
    func resolveDocumentPath(parentFileID: String, maskedName: String) -> String?
    func maskedChildPath(parentFileID: String, maskedName: String) -> String?
    func resolveChild(in parentPath: String, maskedName: String) -> String?
    func childResolutionReason(parentPath: String, maskedName: String) -> String?
}

final class PathResolver: PathResolving {
    private let volumePath: URL
    private let deviceID: Int32
    private var localPathCache: [String: String?] = [:]
    private var directoryEntriesCache: [String: [URL]?] = [:]
    private var directoryFailures: [String: String] = [:]
    private var childCache: [String: String?] = [:]
    private var childFailures: [String: String] = [:]

    init(volumePath: URL) throws {
        self.volumePath = volumePath

        var statBuffer = stat()
        guard stat(volumePath.path, &statBuffer) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "无法读取 volume 设备号: \(volumePath.path)"]
            )
        }
        self.deviceID = statBuffer.st_dev
    }

    func localPath(for itemID: String) -> String? {
        if let cached = localPathCache[itemID] {
            return cached
        }

        let inodePath = "/.vol/\(deviceID)/\(itemID)"
        let resolved = resolveKernelPath(at: inodePath)
        localPathCache[itemID] = resolved
        return resolved
    }

    func localDirectoryPath(for fileID: String) -> String? {
        localPath(for: fileID)
    }

    func resolveDocumentPath(parentFileID: String, maskedName: String) -> String? {
        guard let parent = localDirectoryPath(for: parentFileID) else {
            return nil
        }
        return resolveChild(in: parent, maskedName: maskedName)
    }

    func maskedChildPath(parentFileID: String, maskedName: String) -> String? {
        guard let parent = localDirectoryPath(for: parentFileID) else {
            return nil
        }
        let normalizedName = maskedName.hasSuffix("/") ? String(maskedName.dropLast()) : maskedName
        return URL(fileURLWithPath: parent).appendingPathComponent(normalizedName).path
    }

    func resolveChild(in parentPath: String, maskedName: String) -> String? {
        let cacheKey = "\(parentPath)|\(maskedName)"
        if let cached = childCache[cacheKey] {
            return cached
        }

        let result = resolveChildOnce(in: parentPath, maskedName: maskedName)
        childCache[cacheKey] = result.path
        if let reason = result.failureReason {
            childFailures[cacheKey] = reason
        } else {
            childFailures.removeValue(forKey: cacheKey)
        }
        return result.path
    }

    func childResolutionReason(parentPath: String, maskedName: String) -> String? {
        childFailures["\(parentPath)|\(maskedName)"]
    }

    private func resolveKernelPath(at path: String) -> String? {
        let flags = O_RDONLY | O_CLOEXEC
        let descriptor = open(path, flags)
        guard descriptor >= 0 else {
            return nil
        }
        defer { close(descriptor) }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
            return nil
        }

        let pathBytes = buffer.prefix { $0 != 0 }
        return String(decoding: pathBytes.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private func resolveChildOnce(in parentPath: String, maskedName: String) -> (path: String?, failureReason: String?) {
        guard let entries = directoryEntries(for: parentPath) else {
            return (nil, directoryFailures[parentPath])
        }

        let normalizedName = maskedName.hasSuffix("/") ? String(maskedName.dropLast()) : maskedName
        let exactPath = URL(fileURLWithPath: parentPath).appendingPathComponent(normalizedName).path
        if FileManager.default.fileExists(atPath: exactPath) {
            return (exactPath, nil)
        }

        let requiresDirectory = maskedName.hasSuffix("/")
        let candidates = entries.filter { entry in
            guard MaskedNameMatcher.matches(maskedName: normalizedName, candidate: entry.lastPathComponent) else {
                return false
            }

            if !requiresDirectory {
                return true
            }

            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }

        if candidates.count == 1 {
            return (candidates[0].path, nil)
        }
        if candidates.count > 1 {
            return (nil, "ambiguous-match")
        }
        return (nil, "no-match")
    }

    private func directoryEntries(for parentPath: String) -> [URL]? {
        if let cached = directoryEntriesCache[parentPath] {
            return cached
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            directoryEntriesCache[parentPath] = nil
            directoryFailures[parentPath] = "parent-not-dir"
            return nil
        }

        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: parentPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            directoryEntriesCache[parentPath] = entries
            directoryFailures.removeValue(forKey: parentPath)
            return entries
        } catch {
            directoryEntriesCache[parentPath] = nil
            let nsError = error as NSError
            directoryFailures[parentPath] = nsError.domain == NSCocoaErrorDomain ? "dir-list-denied" : "dir-list-failed"
            return nil
        }
    }
}
