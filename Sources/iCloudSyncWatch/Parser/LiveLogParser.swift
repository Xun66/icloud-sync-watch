import Foundation

private enum CompletionPolicy {
    case emitOnce
    case requireStart
    case requireStartOrDataless
}

private enum TransitionStatus {
    case started
    case completed
}

final class LiveLogParser {
    private let resolver: PathResolving

    private var docPaths: [String: String] = [:]
    private var providerPaths: [String: String] = [:]
    private var uploadStates: [String: TransitionStatus] = [:]
    private var downloadStates: [String: TransitionStatus] = [:]
    private var deleteStates: [String: TransitionStatus] = [:]
    private var directoryCreateStates: [String: TransitionStatus] = [:]
    private var directoryDeleteStates: [String: TransitionStatus] = [:]
    private var pathSizes: [String: Int] = [:]
    private var decodeFailures: [String: String] = [:]

    init(resolver: PathResolving) {
        self.resolver = resolver
    }

    func feed(line: String, timestamp: Date = Date()) -> [ParsedSyncEvent] {
        observe(line: line)

        var events: [ParsedSyncEvent] = []
        events += handleTransition(
            action: .upload,
            line: line,
            timestamp: timestamp,
            startPath: pathForUpload(line: line, state: "uploading"),
            endPath: pathForUpload(line: line, state: "uploaded"),
            stateMap: &uploadStates,
            completionPolicy: .requireStart,
            fileOnly: true
        )
        events += handleTransition(
            action: .download,
            line: line,
            timestamp: timestamp,
            startPath: pathForDownloading(line: line),
            endPath: pathForDownloaded(line: line),
            stateMap: &downloadStates,
            completionPolicy: .requireStartOrDataless,
            fileOnly: true
        )
        events += handleTransition(
            action: .deleteFile,
            line: line,
            timestamp: timestamp,
            startPath: pathForDeleteStart(line: line),
            endPath: pathForDeleteEnd(line: line),
            stateMap: &deleteStates,
            completionPolicy: .emitOnce,
            fileOnly: true
        )
        events += handleTransition(
            action: .createDirectory,
            line: line,
            timestamp: timestamp,
            startPath: pathForDirectoryCreateStart(line: line),
            endPath: pathForDirectoryCreateEnd(line: line),
            stateMap: &directoryCreateStates,
            completionPolicy: .emitOnce,
            fileOnly: false
        )
        events += handleTransition(
            action: .deleteDirectory,
            line: line,
            timestamp: timestamp,
            startPath: pathForDirectoryDeleteStart(line: line),
            endPath: pathForDirectoryDeleteEnd(line: line),
            stateMap: &directoryDeleteStates,
            completionPolicy: .emitOnce,
            fileOnly: false
        )

        if let event = pathChangeEvent(line: line, timestamp: timestamp) {
            events.append(event)
        }

        return events
    }

    private func observe(line: String) {
        captureLocalItems(line: line)
        captureProviderLinks(line: line)
        captureKnownSizes(line: line)
    }

    private func captureLocalItems(line: String) {
        for groups in Patterns.docItem.allMatches(in: line) where groups.count == 3 {
            let docID = groups[0]
            let parentID = groups[1]
            let maskedName = groups[2]
            if let resolved = resolveDocumentPath(parentFileID: parentID, maskedName: maskedName, line: line) {
                docPaths[docID] = docPaths[docID] ?? resolved
            }
        }

        if let inodePath = pathFromItemInode(line: line) {
            for groups in Patterns.docID.allMatches(in: line) where !groups.isEmpty {
                docPaths[groups[0]] = docPaths[groups[0]] ?? inodePath
            }
        }

        for groups in Patterns.directoryItem.allMatches(in: line) where !groups.isEmpty {
            let fileID = groups[0]
            if let resolved = resolver.localDirectoryPath(for: fileID) {
                providerPaths[fileID] = providerPaths[fileID] ?? resolved
            }
        }
    }

    private func captureProviderLinks(line: String) {
        for groups in Patterns.reconcile.allMatches(in: line) where groups.count == 3 {
            let kind = groups[0]
            let identifier = groups[1]
            let providerID = groups[2]
            let path: String?

            if kind == "docID" {
                path = docPaths[identifier]
            } else {
                path = resolver.localDirectoryPath(for: identifier)
            }

            if let path {
                providerPaths[providerID] = providerPaths[providerID] ?? path
            }
        }

        for groups in Patterns.propagatedDocTarget.allMatches(in: line) where groups.count == 2 {
            let docID = groups[0]
            let providerID = groups[1]
            if let path = docPaths[docID] {
                providerPaths[providerID] = providerPaths[providerID] ?? path
            }
        }

        for groups in Patterns.propagatedDocActual.allMatches(in: line) where groups.count == 2 {
            let docID = groups[0]
            let providerID = groups[1]
            if let path = docPaths[docID] {
                providerPaths[providerID] = providerPaths[providerID] ?? path
            }
        }

        for groups in Patterns.propagatedFileTarget.allMatches(in: line) where groups.count == 2 {
            let fileID = groups[0]
            let providerID = groups[1]
            if let path = resolver.localDirectoryPath(for: fileID) {
                providerPaths[providerID] = providerPaths[providerID] ?? path
            }
        }

        for groups in Patterns.providerItem.allMatches(in: line) where groups.count == 3 {
            let providerID = groups[0]
            let parentProviderID = groups[1]
            let maskedName = groups[2]
            guard let parent = providerPaths[parentProviderID] else {
                continue
            }
            if let resolved = resolver.resolveChild(in: parent, maskedName: maskedName) {
                providerPaths[providerID] = providerPaths[providerID] ?? resolved
            }
        }
    }

    private func captureKnownSizes(line: String) {
        guard let size = latestSize(line: line) else {
            return
        }

        for docID in documentIDs(in: line) {
            if let path = docPaths[docID] {
                pathSizes[path] = size
            }
        }

        if let providerPath = pathForProviderContext(line: line) {
            pathSizes[providerPath] = size
        }
    }

    private func handleTransition(
        action: SyncAction,
        line: String,
        timestamp: Date,
        startPath: String?,
        endPath: String?,
        stateMap: inout [String: TransitionStatus],
        completionPolicy: CompletionPolicy,
        fileOnly: Bool
    ) -> [ParsedSyncEvent] {
        var events: [ParsedSyncEvent] = []

        if let startPath, matchesScope(path: startPath, fileOnly: fileOnly) {
            if stateMap[startPath] != .started {
                let size = sizeForPath(startPath, line: line)
                events.append(
                    ParsedSyncEvent(
                        action: action,
                        phase: .started,
                        primaryPath: startPath,
                        secondaryPath: nil,
                        fileSize: size,
                        decodeReason: decodeFailures[startPath],
                        triggerReason: triggerReason(for: action, line: line),
                        timestamp: timestamp
                    )
                )
                stateMap[startPath] = .started
            }
        }

        if let endPath, matchesScope(path: endPath, fileOnly: fileOnly) {
            let currentState = stateMap[endPath]
            guard currentState != .completed else {
                return events
            }
            guard completionAllowed(
                currentState: currentState,
                completionPolicy: completionPolicy,
                line: line
            ) else {
                return events
            }

            let size = sizeForPath(endPath, line: line)
            events.append(
                ParsedSyncEvent(
                    action: action,
                    phase: .completed,
                    primaryPath: endPath,
                    secondaryPath: nil,
                    fileSize: size,
                    decodeReason: decodeFailures[endPath],
                    triggerReason: triggerReason(for: action, line: line),
                    timestamp: timestamp
                )
            )
            stateMap[endPath] = .completed
        }

        return events
    }

    private func completionAllowed(
        currentState: TransitionStatus?,
        completionPolicy: CompletionPolicy,
        line: String
    ) -> Bool {
        switch completionPolicy {
        case .emitOnce:
            return true
        case .requireStart:
            return currentState == .started
        case .requireStartOrDataless:
            return currentState == .started || line.contains("diffs:dataless")
        }
    }

    private func matchesScope(path: String, fileOnly: Bool) -> Bool {
        guard fileOnly else {
            return true
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return !isDirectory.boolValue
    }

    private func resolveDocumentPath(parentFileID: String, maskedName: String, line: String) -> String? {
        if let resolved = resolver.resolveDocumentPath(parentFileID: parentFileID, maskedName: maskedName) {
            decodeFailures.removeValue(forKey: resolved)
            return resolved
        }

        if let inodePath = pathFromItemInode(line: line) {
            decodeFailures.removeValue(forKey: inodePath)
            return inodePath
        }

        guard let maskedPath = resolver.maskedChildPath(parentFileID: parentFileID, maskedName: maskedName) else {
            return nil
        }

        let parentPath = URL(fileURLWithPath: maskedPath).deletingLastPathComponent().path
        if let reason = resolver.childResolutionReason(parentPath: parentPath, maskedName: maskedName) {
            decodeFailures[maskedPath] = reason
        }
        return maskedPath
    }

    private func pathFromItemInode(line: String) -> String? {
        for groups in Patterns.fileInode.allMatches(in: line) where !groups.isEmpty {
            if let path = resolver.localPath(for: groups[0]) {
                return path
            }
        }
        return nil
    }

    private func pathForUpload(line: String, state: String) -> String? {
        guard line.contains("ul:\(state)") else {
            return nil
        }

        let paths = documentIDs(in: line).compactMap { docPaths[$0] }
        if let first = paths.first {
            return first
        }
        return pathForProviderContext(line: line)
    }

    private func pathForDownloading(line: String) -> String? {
        guard let groups = Patterns.fetchContent.firstMatch(in: line), let providerID = groups.first else {
            return nil
        }
        return providerPaths[providerID]
    }

    private func pathForDownloaded(line: String) -> String? {
        guard let groups = Patterns.downloadEnd.firstMatch(in: line), let docID = groups.first else {
            return nil
        }
        return docPaths[docID]
    }

    private func pathForDeleteStart(line: String) -> String? {
        guard let groups = Patterns.deleteStart.firstMatch(in: line), let docID = groups.first else {
            return nil
        }
        return docPaths[docID]
    }

    private func pathForDeleteEnd(line: String) -> String? {
        guard let groups = Patterns.deleteEnd.firstMatch(in: line), let docID = groups.first else {
            return nil
        }
        return docPaths[docID]
    }

    private func pathForDirectoryCreateStart(line: String) -> String? {
        guard let groups = Patterns.directoryCreateStart.firstMatch(in: line), let fileID = groups.first else {
            return nil
        }
        return directoryPath(for: fileID)
    }

    private func pathForDirectoryCreateEnd(line: String) -> String? {
        guard let groups = Patterns.directoryCreateEnd.firstMatch(in: line), let fileID = groups.first else {
            return nil
        }
        return directoryPath(for: fileID)
    }

    private func pathForDirectoryDeleteStart(line: String) -> String? {
        guard let groups = Patterns.directoryDeleteStart.firstMatch(in: line), let fileID = groups.first else {
            return nil
        }
        return directoryPath(for: fileID)
    }

    private func pathForDirectoryDeleteEnd(line: String) -> String? {
        guard let groups = Patterns.directoryDeleteEnd.firstMatch(in: line), let fileID = groups.first else {
            return nil
        }
        return directoryPath(for: fileID)
    }

    private func directoryPath(for fileID: String) -> String? {
        if let path = providerPaths[fileID] {
            return path
        }
        return resolver.localDirectoryPath(for: fileID)
    }

    private func pathChangeEvent(line: String, timestamp: Date) -> ParsedSyncEvent? {
        if let event = documentPathChangeEvent(line: line, timestamp: timestamp) {
            return event
        }
        return directoryPathChangeEvent(line: line, timestamp: timestamp)
    }

    private func documentPathChangeEvent(line: String, timestamp: Date) -> ParsedSyncEvent? {
        guard let groups = Patterns.documentPathUpdate.firstMatch(in: line), groups.count == 6 else {
            return nil
        }

        let docID = groups[0]
        let newParentID = groups[3]
        let newName = groups[4]
        let diffs = groups[5]
        let oldPath = docPaths[docID]
        let newPath = resolveDocumentPath(parentFileID: newParentID, maskedName: newName, line: line)

        if let newPath {
            docPaths[docID] = newPath
        }

        return formatPathChangeEvent(
            oldPath: oldPath,
            newPath: newPath,
            diffs: diffs,
            fileAction: (.renameFile, .moveFile),
            timestamp: timestamp
        )
    }

    private func directoryPathChangeEvent(line: String, timestamp: Date) -> ParsedSyncEvent? {
        if let event = directoryUpdateCompletionEvent(line: line, timestamp: timestamp) {
            return event
        }
        if let event = directorySnapshotChangeEvent(line: line, timestamp: timestamp) {
            return event
        }

        guard let groups = Patterns.directoryPathUpdate.firstMatch(in: line), groups.count == 6 else {
            return nil
        }

        let fileID = groups[0]
        let diffs = groups[5]
        let oldPath = providerPaths[fileID]
        let newPath = resolver.localDirectoryPath(for: fileID)

        if let newPath {
            providerPaths[fileID] = newPath
        }

        return formatPathChangeEvent(
            oldPath: oldPath,
            newPath: newPath,
            diffs: diffs,
            fileAction: (.renameDirectory, .moveDirectory),
            timestamp: timestamp
        )
    }

    private func directoryUpdateCompletionEvent(line: String, timestamp: Date) -> ParsedSyncEvent? {
        guard let groups = Patterns.directoryUpdateCompletion.firstMatch(in: line), groups.count == 4 else {
            return nil
        }

        let fileID = groups[0]
        let parentRef = groups[1]
        let diffs = groups[3]
        let oldPath = providerPaths[fileID]
        let newPath = resolver.localPath(for: fileID)

        if let newPath {
            providerPaths[fileID] = newPath
        }

        let normalizedDiffs = normalizedDiffs(from: diffs)
        guard let oldPath else {
            return nil
        }

        if (parentRef == "trash" || parentRef == ".trash"), normalizedDiffs.contains("parentID") {
            return ParsedSyncEvent(
                action: .deleteDirectory,
                phase: .completed,
                primaryPath: oldPath,
                secondaryPath: nil,
                fileSize: nil,
                decodeReason: nil,
                triggerReason: diffs,
                timestamp: timestamp
            )
        }

        return formatPathChangeEvent(
            oldPath: oldPath,
            newPath: newPath,
            diffs: diffs,
            fileAction: (.renameDirectory, .moveDirectory),
            timestamp: timestamp
        )
    }

    private func directorySnapshotChangeEvent(line: String, timestamp: Date) -> ParsedSyncEvent? {
        guard let groups = Patterns.directorySnapshotChange.firstMatch(in: line), groups.count == 4 else {
            return nil
        }

        let fileID = groups[0]
        let parentRef = groups[1]
        let diffs = groups[3]
        let oldPath = providerPaths[fileID]
        let newPath = resolver.localPath(for: fileID)

        if let newPath {
            providerPaths[fileID] = newPath
        }

        let normalizedDiffs = normalizedDiffs(from: diffs)
        guard let oldPath else {
            return nil
        }

        if (parentRef == "trash" || parentRef == ".trash"), normalizedDiffs.contains("parentID") {
            return ParsedSyncEvent(
                action: .deleteDirectory,
                phase: .completed,
                primaryPath: oldPath,
                secondaryPath: nil,
                fileSize: nil,
                decodeReason: nil,
                triggerReason: diffs,
                timestamp: timestamp
            )
        }

        return formatPathChangeEvent(
            oldPath: oldPath,
            newPath: newPath,
            diffs: diffs,
            fileAction: (.renameDirectory, .moveDirectory),
            timestamp: timestamp
        )
    }

    private func formatPathChangeEvent(
        oldPath: String?,
        newPath: String?,
        diffs: String,
        fileAction: (rename: SyncAction, move: SyncAction),
        timestamp: Date
    ) -> ParsedSyncEvent? {
        guard let oldPath, let newPath, oldPath != newPath else {
            return nil
        }

        let normalizedDiffs = normalizedDiffs(from: diffs)
        if normalizedDiffs.contains("parentID") {
            return ParsedSyncEvent(
                action: fileAction.move,
                phase: .completed,
                primaryPath: oldPath,
                secondaryPath: newPath,
                fileSize: nil,
                decodeReason: nil,
                triggerReason: diffs,
                timestamp: timestamp
            )
        }
        if normalizedDiffs.contains("filename") {
            return ParsedSyncEvent(
                action: fileAction.rename,
                phase: .completed,
                primaryPath: oldPath,
                secondaryPath: newPath,
                fileSize: nil,
                decodeReason: nil,
                triggerReason: diffs,
                timestamp: timestamp
            )
        }
        return nil
    }

    private func normalizedDiffs(from diffs: String) -> Set<String> {
        Set(diffs.replacingOccurrences(of: " ", with: "").split(separator: "|").map(String.init))
    }

    private func documentIDs(in line: String) -> [String] {
        Patterns.docID.allMatches(in: line).compactMap(\.first)
    }

    private func latestSize(line: String) -> Int? {
        let sizes = Patterns.fileSize.allMatches(in: line).compactMap { groups -> Int? in
            guard let first = groups.first else {
                return nil
            }
            return Int(first)
        }
        return sizes.last
    }

    private func sizeForPath(_ path: String, line: String) -> Int? {
        if let latest = latestSize(line: line) {
            pathSizes[path] = latest
            return latest
        }
        return pathSizes[path]
    }

    private func pathForProviderContext(line: String) -> String? {
        if let groups = Patterns.fpItem.firstMatch(in: line), let providerID = groups.first, let path = providerPaths[providerID] {
            return path
        }
        if let groups = Patterns.providerDocument.firstMatch(in: line), let providerID = groups.first, let path = providerPaths[providerID] {
            return path
        }
        return nil
    }

    private func triggerReason(for action: SyncAction, line: String) -> String? {
        switch action {
        case .upload, .download:
            if let why = Patterns.why.firstMatch(in: line)?.first {
                return why
            }
            return Patterns.diffs.firstMatch(in: line)?.first
        case .deleteFile:
            if let deleteReason = Patterns.deleteStart.firstMatch(in: line), deleteReason.count > 1 {
                return deleteReason[1]
            }
            if let why = Patterns.why.firstMatch(in: line)?.first {
                return why
            }
            return Patterns.diffs.firstMatch(in: line)?.first
        case .createDirectory, .deleteDirectory, .renameFile, .moveFile, .renameDirectory, .moveDirectory:
            return Patterns.diffs.firstMatch(in: line)?.first ?? Patterns.why.firstMatch(in: line)?.first
        }
    }
}

private enum Patterns {
    static let docItem = Regex(#"<[is]:docID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)""#)
    static let directoryItem = Regex(#"<[is]:fileID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir\b"#)
    static let reconcile = Regex(#"<fs:[^>]*?(docID|fileID)\(([^)]+)\)[^>]*?>\s*<->\s*<fp:[^>]*?\s([a-z0-9]+)\s"#)
    static let propagatedDocTarget = Regex(#"propagated:<docID\((\d+)\).*?target:<id:([a-z0-9]+)\b"#)
    static let propagatedDocActual = Regex(#"propagated:<docID\((\d+)\).*?<actual:<s:([a-z0-9]+)\b"#)
    static let propagatedFileTarget = Regex(#"propagated:<fileID\((\d+)\).*?target:<id:([a-z0-9]+)\b"#)
    static let providerItem = Regex(#"<s:([a-z0-9]+)\s+p:([a-z0-9]+)\s+n:"([^"]+)"\s+doc"#)
    static let fetchContent = Regex(#"<FP\d+\s+[^\n>]*fetch-content\(([^)]+)\)"#)
    static let downloadEnd = Regex(#"done executing <J\d+ ✅  update-item\(.*target:<id:docID\((\d+)\).*why:[^>]*itemChangedRemotely"#)
    static let directoryCreateStart = Regex(#"reconciliation insert:.*<fs:[^>]*fileID\((\d+)\)[^>]*>.*\sdir\b"#)
    static let directoryCreateEnd = Regex(#"itemUpdatedInFSSnapshot\(from: nil, to: Optional\(<s:fileID\((\d+)\).*?\sdir\b.*?\), diffs: all\)"#)
    static let deleteStart = Regex(#"reconciliation delete:.*<fs:[^>]*docID\((\d+)\)[^>]*delete:([A-Za-z0-9_|-]+)"#)
    static let deleteEnd = Regex(#"itemUpdatedInFSSnapshot\(from: Optional\(<s:docID\((\d+)\).*?\), to: nil, diffs: all\)"#)
    static let directoryDeleteStart = Regex(#"reconciliation delete:.*<fs:[^>]*fileID\((\d+)\)[^>]*delete:([A-Za-z0-9_|-]+).*?>.*\sdir\b"#)
    static let directoryDeleteEnd = Regex(#"itemUpdatedInFSSnapshot\(from: Optional\(<s:fileID\((\d+)\).*?\sdir\b.*?\), to: nil, diffs: all\)"#)
    static let documentPathUpdate = Regex(#"itemUpdatedInFSSnapshot\(from: Optional\(<s:docID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)".*?\), to: Optional\(<s:docID\(\1\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)".*?\), diffs:\s*([A-Za-z0-9_| ]+)\)"#)
    static let directoryPathUpdate = Regex(#"itemUpdatedInFSSnapshot\(from: Optional\(<s:fileID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir.*?\), to: Optional\(<s:fileID\(\1\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir.*?\), diffs:\s*([A-Za-z0-9_| ]+)\)"#)
    static let docID = Regex(#"\bdocID\((\d+)\)"#)
    static let fpItem = Regex(#"FPItem [^:]+:([a-z0-9]+)\b"#)
    static let providerDocument = Regex(#"<s:([a-z0-9]+)\s+p:[^>]+n:"[^"]+"\s+doc"#)
    static let fileSize = Regex(#"\bsz:(\d+)\b"#)
    static let fileInode = Regex(#"(?:file-ino|content:fid)\((\d+)\)"#)
    static let diffs = Regex(#"diffs:([A-Za-z0-9_|-]+)"#)
    static let why = Regex(#"why:([A-Za-z0-9_|-]+)"#)
    static let directorySnapshotChange = Regex(#"FS snapshot mutation: update<s:fileID\((\d+)\)\s+p:([^ ]+)\s+n:"([^"]+)"\s+dir.*?>\s+diffs:([A-Za-z0-9_|-]+)\b"#)
    static let directoryUpdateCompletion = Regex(#"done executing <J\d+ .*?update-item\(propagated:<fileID\((\d+)\).*?requested:<p:([^ ]+) n:"([^"]+)" dir .*?diffs:([A-Za-z0-9_|-]+)\)"#)
}
