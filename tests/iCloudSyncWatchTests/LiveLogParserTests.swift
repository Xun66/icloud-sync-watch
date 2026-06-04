import Foundation
import Testing
@testable import iCloudSyncWatch

struct LiveLogParserTests {
    @Test
    func emitsUploadLifecycle() {
        let root = URL(fileURLWithPath: "/tmp")
        let target = root.appendingPathComponent("target_file.log").path
        let resolver = FakeResolver(
            localDirectoryPaths: ["12345": root.path],
            documentPaths: ["12345|t{9}e.log": target]
        )
        let parser = LiveLogParser(resolver: resolver)

        let lines = [
            #"[dbg] Handling FSEvent for <i:docID(514576) p:fileID(12345) n:"t{9}e.log" doc sz:363 m:rw- ct:0 mt:0>"#,
            #"[note] done executing <J1 ✅  update-item(propagated:<docID(514576) dbver:12 domver:<nil>> target:<id:f3c6be sver:{blob16} cver:{blob41}> requested:<p:n3c6b1 n:"t{9}e.log" doc sz:363 m:rw-> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:f3c6be p:n3c6b1 n:"t{9}e.log" doc sz:363 m:rw- nsattr:<cap:rwdpfTe-- l:"t{9}e.log" ul:uploading userInfo:<4 keys>>>>"#,
            #"[info] item changed <FPItem 0x1:f3c6be l:"t{9}e.log" p:n3c6b1 sz:363 bytes cap:rwdpfetT---- ul:uploaded dl:current spd:com.apple.CloudDocs>"#,
        ]

        let events = lines.flatMap { parser.feed(line: $0, timestamp: Date(timeIntervalSince1970: 1)) }

        #expect(events.count == 2)
        #expect(events[0].action == .upload)
        #expect(events[0].phase == .started)
        #expect(events[0].primaryPath == target)
        #expect(events[1].phase == .completed)
        #expect(events[1].fileSize == 363)
        #expect(events[0].triggerReason == "itemChangedRemotely|contentUpdate")
    }

    @Test
    func emitsDirectoryDeletionWhenMovedToTrash() {
        let oldPath = "/tmp/temp-dir"
        let resolver = FakeResolver(
            localPaths: ["116923617": oldPath],
            localDirectoryPaths: ["116923617": oldPath]
        )
        let parser = LiveLogParser(resolver: resolver)

        _ = parser.feed(
            line: #"[info] item changed <i:fileID(116923617) p:fileID(11111) n:"temp-dir" dir child:0 m:rwx ct:1 mt:1>"#,
            timestamp: .now
        )

        let events = parser.feed(
            line: #"[info] done executing <J2 ✅  update-item(propagated:<fileID(116923617) dbver:3 domver:<nil>> target:<id:n3c746 sver:{blob16} cver:> requested:<p:.trash n:"t{11}3" dir child:0 m:rwx ct:1 mt:2> diffs:filename|parentID|structure) why:itemChangedRemotely sched:utility#1780543693.088181> →  <actual:<s:n3c746 p:.trash n:"t{11}3/" dir child:65533 m:rwx ct:1 mt:2 ul:uploading userInfo:<7 keys> cp:system>> stillPending: shouldFetch:false>"#,
            timestamp: .now
        )

        #expect(events.count == 1)
        #expect(events[0].action == .deleteDirectory)
        #expect(events[0].phase == .completed)
        #expect(events[0].primaryPath == oldPath)
    }
}

private final class FakeResolver: PathResolving {
    private let localPaths: [String: String]
    private let localDirectoryPaths: [String: String]
    private let documentPaths: [String: String]
    private let maskedPaths: [String: String]
    private let childPaths: [String: String]
    private let childReasons: [String: String]

    init(
        localPaths: [String: String] = [:],
        localDirectoryPaths: [String: String] = [:],
        documentPaths: [String: String] = [:],
        maskedPaths: [String: String] = [:],
        childPaths: [String: String] = [:],
        childReasons: [String: String] = [:]
    ) {
        self.localPaths = localPaths
        self.localDirectoryPaths = localDirectoryPaths
        self.documentPaths = documentPaths
        self.maskedPaths = maskedPaths
        self.childPaths = childPaths
        self.childReasons = childReasons
    }

    func localPath(for itemID: String) -> String? {
        localPaths[itemID]
    }

    func localDirectoryPath(for fileID: String) -> String? {
        localDirectoryPaths[fileID]
    }

    func resolveDocumentPath(parentFileID: String, maskedName: String) -> String? {
        documentPaths["\(parentFileID)|\(maskedName)"]
    }

    func maskedChildPath(parentFileID: String, maskedName: String) -> String? {
        maskedPaths["\(parentFileID)|\(maskedName)"]
    }

    func resolveChild(in parentPath: String, maskedName: String) -> String? {
        childPaths["\(parentPath)|\(maskedName)"]
    }

    func childResolutionReason(parentPath: String, maskedName: String) -> String? {
        childReasons["\(parentPath)|\(maskedName)"]
    }
}
