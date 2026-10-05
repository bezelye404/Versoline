import Foundation

/// The ceilings of the in-memory caches, in one place so a test can hold them to the project's low-RAM goal.
/// Anything cached on disk is fetched again when needed; these only decide how much stays in memory meanwhile.
enum MemoryLimits {
    static let megabyte = 1024 * 1024

    /// Extracted article pages kept in memory (the rest are read from the disk cache).
    static let readerPages = (count: 5, bytes: 2 * megabyte)
    /// Decoded site icons.
    static let favicons = (count: 50, bytes: 2 * megabyte)
    /// Downsampled thumbnails and article images.
    static let images = (count: 25, bytes: 2 * megabyte)
    /// Image files kept on disk before the oldest are removed.
    static let imageDiskBytes = 30 * megabyte
    /// Total size of the reader's page cache on disk.
    static let readerDiskBytes = 150 * megabyte
}
