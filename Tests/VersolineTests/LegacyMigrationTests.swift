import Testing
import Foundation
@testable import Versoline

@Suite("LegacyMigration Tests")
@MainActor
struct LegacyMigrationTests {

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Migrates successfully when legacy directory exists and target does not")
    func migrationWhenLegacyExistsAndNewDoesNotExist() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        let legacyDir = tempDir.appendingPathComponent("EasyRSS", isDirectory: true)
        let subDir = legacyDir.appendingPathComponent("Favicons", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let testFile = legacyDir.appendingPathComponent("feeds.json")
        let sampleData = "{\"feeds\": []}".data(using: .utf8)!
        try sampleData.write(to: testFile)

        let result = LegacyMigration.runMigration(customAppSupportURL: tempDir)

        #expect(result != .notNeeded)
        #expect(result != .alreadyCompleted)

        let newDir = tempDir.appendingPathComponent("Versoline", isDirectory: true)
        let newTestFile = newDir.appendingPathComponent("feeds.json")
        let markerFile = newDir.appendingPathComponent(".migrated-from-easyrss")

        #expect(FileManager.default.fileExists(atPath: newTestFile.path))
        #expect(FileManager.default.fileExists(atPath: markerFile.path))
        // Verify non-destructive: original EasyRSS directory must still exist!
        #expect(FileManager.default.fileExists(atPath: testFile.path))
    }

    @Test("Skips migration if marker file already exists in Versoline")
    func migrationWhenAlreadyCompleted() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        let newDir = tempDir.appendingPathComponent("Versoline", isDirectory: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let markerFile = newDir.appendingPathComponent(".migrated-from-easyrss")
        try "migratedAt=2026-09-25".data(using: .utf8)!.write(to: markerFile)

        let result = LegacyMigration.runMigration(customAppSupportURL: tempDir)
        #expect(result == .alreadyCompleted)
    }

    @Test("Recovers and recopies safely if a previous migration was interrupted / half-copied")
    func migrationWhenPartialCopyExists() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        // Setup legacy with complete data
        let legacyDir = tempDir.appendingPathComponent("EasyRSS", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let originalFile = legacyDir.appendingPathComponent("articles.json")
        try "{\"articles\": [1,2,3]}".data(using: .utf8)!.write(to: originalFile)

        // Setup incomplete Versoline without marker
        let newDir = tempDir.appendingPathComponent("Versoline", isDirectory: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let partialFile = newDir.appendingPathComponent("corrupted.tmp")
        try "corrupt".data(using: .utf8)!.write(to: partialFile)

        let result = LegacyMigration.runMigration(customAppSupportURL: tempDir)

        let newArticlesFile = newDir.appendingPathComponent("articles.json")
        let markerFile = newDir.appendingPathComponent(".migrated-from-easyrss")

        #expect(FileManager.default.fileExists(atPath: newArticlesFile.path))
        #expect(FileManager.default.fileExists(atPath: markerFile.path))
        #expect(!FileManager.default.fileExists(atPath: partialFile.path))
    }

    @Test("Returns notNeeded when neither legacy nor new directory exists")
    func migrationWhenNoLegacyExists() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        let result = LegacyMigration.runMigration(customAppSupportURL: tempDir)
        #expect(result == .notNeeded)
    }

    @Test("Migrates empty legacy directory successfully")
    func migrationWhenLegacyIsEmpty() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        let legacyDir = tempDir.appendingPathComponent("EasyRSS", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        let result = LegacyMigration.runMigration(customAppSupportURL: tempDir)
        let markerFile = tempDir.appendingPathComponent("Versoline/.migrated-from-easyrss")

        #expect(FileManager.default.fileExists(atPath: markerFile.path))
        #expect(FileManager.default.fileExists(atPath: legacyDir.path))
    }
}
