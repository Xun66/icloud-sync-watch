import Foundation
import Testing
@testable import iCloudSyncWatch

struct FinderRevealTargetTests {
    @Test
    func selectsExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("report.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let target = FinderRevealTarget.resolve(path: fileURL.path)

        #expect(target == .select(fileURL))
    }

    @Test
    func fallsBackToClosestExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedDirectory = directory.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let missingFileURL = nestedDirectory.appendingPathComponent("missing/report.txt")
        let target = FinderRevealTarget.resolve(path: missingFileURL.path)

        #expect(target == .openDirectory(nestedDirectory))
    }

    @Test
    func fallsBackFromDeletedDirectoryToExistingParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parentDirectory = directory.appendingPathComponent("parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let deletedDirectoryURL = parentDirectory.appendingPathComponent("deleted", isDirectory: true)
        let target = FinderRevealTarget.resolve(path: deletedDirectoryURL.path)

        #expect(target == .openDirectory(parentDirectory))
    }
}
