import Foundation
@testable import Versoline

/// A `FeedStore` wired to throwaway directories so tests never touch real user data.
@MainActor
struct TestStore {
    let store: FeedStore
    let directory: URL
    let cacheDirectory: URL

    init(preparing prepare: (URL) throws -> Void = { _ in }) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        directory = root.appendingPathComponent("store", isDirectory: true)
        cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try prepare(directory)
        store = FeedStore(storageDirectory: directory, readerCache: ReaderModeExtractor(cacheDirectory: cacheDirectory))
    }

    /// Opens a second store on the same directory (simulates a relaunch).
    func reopen() -> FeedStore {
        FeedStore(storageDirectory: directory, readerCache: ReaderModeExtractor(cacheDirectory: cacheDirectory))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}
