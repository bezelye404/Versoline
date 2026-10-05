import Foundation
import AppKit
import SwiftUI
import ImageIO
import CoreGraphics

/// `NSImage` is not `Sendable` in every SDK this project builds with (Xcode 16 rejects it as a `Task`
/// result), so in-flight image tasks return it inside this box. The image is only used on the main actor.
struct SendableImage: @unchecked Sendable {
    let image: NSImage?
}

@MainActor
final class FaviconService {

    static let shared = FaviconService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var inFlightTasks: [String: Task<SendableImage, Never>] = [:]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    private init() {
        let dir = AppInfo.supportDirectory.appendingPathComponent("Favicons", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
        memoryCache.countLimit = MemoryLimits.favicons.count
        memoryCache.totalCostLimit = MemoryLimits.favicons.bytes
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat = 64) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return NSImage(data: data)
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return NSImage(data: data)
        }

        return NSImage(cgImage: thumbnail, size: NSSize(width: maxPixelSize / 2, height: maxPixelSize / 2))
    }

    func favicon(for hostOrURL: String) async -> NSImage? {
        guard let host = extractHost(from: hostOrURL), !host.isEmpty else { return nil }

        // Memory cache
        let cacheKey = host as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // Disk cache (with downsampling on decode)
        let diskURL = cacheDirectory.appendingPathComponent("\(host).png")
        if fileManager.fileExists(atPath: diskURL.path(percentEncoded: false)),
           let data = try? Data(contentsOf: diskURL),
           let image = Self.downsample(data: data) {
            memoryCache.setObject(image, forKey: cacheKey, cost: 16 * 1024)
            return image
        }

        // Prevent duplicate in-flight network requests
        if let existing = inFlightTasks[host] {
            return await existing.value.image
        }

        let task = Task<SendableImage, Never> {
            let image = await downloadFavicon(forHost: host)
            if let image {
                self.memoryCache.setObject(image, forKey: cacheKey, cost: 16 * 1024)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    Task.detached(priority: .utility) {
                        ImageDownsampleCache.writeCGImageToDisk(cg, destinationURL: diskURL)
                    }
                }
            }
            self.inFlightTasks.removeValue(forKey: host)
            return SendableImage(image: image)
        }

        inFlightTasks[host] = task
        return await task.value.image
    }

    /// Fetches the icon from the site itself, the way a browser would: `/favicon.ico`, then the icon the home page
    /// names. Only the site that publishes the feed is contacted; no icon service ever hears which sites are followed.
    private func downloadFavicon(forHost host: String) async -> NSImage? {
        for candidate in Self.hostsToTry(for: host) {
            if let icon = await fetchIcon(from: "https://\(candidate)/favicon.ico") { return icon }
            if let page = await fetchData(from: "https://\(candidate)/", limit: 150_000) {
                for address in Self.iconAddresses(inHTML: String(decoding: page, as: UTF8.self), pageAddress: "https://\(candidate)/") {
                    if let icon = await fetchIcon(from: address) { return icon }
                }
            }
        }
        return nil
    }

    /// The feed's own host, then its parent domain (`feeds.example.com` is a feed server, `example.com` has the icon).
    static func hostsToTry(for host: String) -> [String] {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return [host] }
        return [host, labels.dropFirst().joined(separator: ".")]
    }

    /// Icons a page names with `<link rel="icon">`, `shortcut icon` or `apple-touch-icon`, best first (touch icons are
    /// the sharpest), as absolute addresses.
    static func iconAddresses(inHTML html: String, pageAddress: String) -> [String] {
        guard let base = URL(string: pageAddress),
              let tags = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let source = html as NSString
        var found: [(rank: Int, address: String)] = []
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range)
            guard let rel = attribute("rel", in: tag)?.lowercased(), let href = attribute("href", in: tag),
                  rel.contains("icon"), let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http" else { continue }
            found.append((rel.contains("apple-touch") ? 0 : 1, url.absoluteString))
        }
        return found.sorted { $0.rank < $1.rank }.map(\.address)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return (tag as NSString).substring(with: match.range(at: group))
        }
        return nil
    }

    private func fetchIcon(from address: String) async -> NSImage? {
        guard let data = await fetchData(from: address, limit: 400_000), !data.isEmpty else { return nil }
        return Self.downsample(data: data)
    }

    private func fetchData(from address: String, limit: Int) async -> Data? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= limit else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func extractHost(from string: String) -> String? {
        if string.contains("://"), let url = URL(string: string) {
            return url.host
        }
        return string.components(separatedBy: "/").first
    }

    func clearDiskCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.removeAllObjects()
    }
}

struct FaviconView: View {

    @AppStorage(AppSettingsKeys.showFavicons) private var showFavicons = true
    let hostOrURL: String
    var size: CGFloat = 16

    @State private var image: NSImage?

    var body: some View {
        Group {
            if showFavicons {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size > 20 ? 4 : 3))
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: size * 0.85))
                        .foregroundStyle(.secondary)
                        .frame(width: size, height: size)
                }
            } else {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .task(id: hostOrURL) {
            guard showFavicons else { return }
            image = await FaviconService.shared.favicon(for: hostOrURL)
        }
    }
}

// MARK: Downsampled images

@MainActor
final class ImageDownsampleCache {
    static let shared = ImageDownsampleCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private var inFlightTasks: [String: Task<SendableImage, Never>] = [:]

    private init() {
        let dir = AppInfo.supportDirectory.appendingPathComponent("ImageCache_v1", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskCacheURL = dir

        memoryCache.countLimit = MemoryLimits.images.count
        memoryCache.totalCostLimit = MemoryLimits.images.bytes
    }

    func clearMemory() {
        memoryCache.removeAllObjects()
    }

    var diskCacheSizeBytes: Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func clearDiskCache() {
        memoryCache.removeAllObjects()
        if let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    func cleanupDiskCache(olderThanDays days: Int = 14) {
        guard days > 0 else { return }
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))
        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoffDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    func enforceQuota(maxSizeBytes: Int64 = Int64(MemoryLimits.imageDiskBytes)) {
        let currentSize = diskCacheSizeBytes
        guard currentSize > maxSizeBytes else { return }
        let targetSize = Int64(Double(maxSizeBytes) * 0.7)

        guard let files = try? fileManager.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let sortedFiles = files.sorted { f1, f2 in
            let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 < d2
        }

        var remainingSize = currentSize
        for file in sortedFiles {
            guard remainingSize > targetSize else { break }
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                try? fileManager.removeItem(at: file)
                remainingSize -= Int64(size)
            }
        }
    }

    private func cacheKey(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)_\(Int(maxPixelSize))"
    }

    private func diskFileURL(for key: String) -> URL {
        let safeName = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(100)
        return diskCacheURL.appendingPathComponent("\(safeName).png")
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        guard AppInfo.isWebAddress(url) else { return nil }
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        let nsKey = key as NSString

        // In-memory check
        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        // Disk cache check
        let diskURL = diskFileURL(for: key)
        if fileManager.fileExists(atPath: diskURL.path(percentEncoded: false)),
           let diskData = try? Data(contentsOf: diskURL),
           let downsampled = Self.downsample(data: diskData, maxPixelSize: maxPixelSize) {
            let cost = Int(maxPixelSize * maxPixelSize * 4)
            memoryCache.setObject(downsampled.nsImage, forKey: nsKey, cost: cost)
            return downsampled.nsImage
        }

        // Deduplicate in-flight network requests
        if let existing = inFlightTasks[key] {
            return await existing.value.image
        }

        let task = Task<SendableImage, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
                    return SendableImage(image: nil)
                }

                guard let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return SendableImage(image: nil)
                }

                let cost = Int(maxPixelSize * maxPixelSize * 4)
                self.memoryCache.setObject(downsampled.nsImage, forKey: nsKey, cost: cost)

                // Stream downsampled thumbnail CGImage directly to PNG on disk with zero intermediate TIFF allocations
                let cgImage = downsampled.cgImage
                Task.detached(priority: .utility) {
                    Self.writeCGImageToDisk(cgImage, destinationURL: diskURL)
                }

                return SendableImage(image: downsampled.nsImage)
            } catch {
                return SendableImage(image: nil)
            }
        }

        inFlightTasks[key] = task
        let result = await task.value.image
        inFlightTasks.removeValue(forKey: key)
        return result
    }

    nonisolated static func writeCGImageToDisk(_ cgImage: CGImage, destinationURL: URL) {
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Decodes straight to thumbnail size, so the full-size bitmap is never held in memory.
    private static func downsample(data: Data, maxPixelSize: CGFloat) -> (nsImage: NSImage, cgImage: CGImage)? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        let nsImg = NSImage(cgImage: thumbnailCG, size: NSSize(width: maxPixelSize / 2, height: maxPixelSize / 2))
        return (nsImg, thumbnailCG)
    }
}

/// A lightweight, drop-in replacement for AsyncImage that guarantees zero memory bloat by downsampling bitmaps on decode.
struct DownsampledImageView<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    private let placeholder: Placeholder

    @State private var loadedImage: NSImage?

    private var maxPixelSize: CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return max(targetSize.width, targetSize.height) * scale
    }

    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder()
    }

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(AppAnimation.quickFeedback))
            } else {
                placeholder
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard let url else {
                loadedImage = nil
                return
            }
            loadedImage = await ImageDownsampleCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

extension DownsampledImageView where Placeholder == Color {
    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0
    ) {
        self.init(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode,
            cornerRadius: cornerRadius,
            placeholder: { Color.secondary.opacity(0.06) }
        )
    }
}

