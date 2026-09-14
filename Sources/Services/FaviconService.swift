import Foundation
import AppKit
import SwiftUI
import ImageIO
import CoreGraphics

@MainActor
final class FaviconService {

    static let shared = FaviconService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyRSS/Favicons", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 2 * 1024 * 1024 // Strict 2MB ceiling for all decoded favicons in RAM
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

        // 1. Memory cache
        let cacheKey = host as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Disk cache (with downsampling on decode)
        let diskURL = cacheDirectory.appendingPathComponent("\(host).png")
        if fileManager.fileExists(atPath: diskURL.path(percentEncoded: false)),
           let data = try? Data(contentsOf: diskURL),
           let image = Self.downsample(data: data) {
            memoryCache.setObject(image, forKey: cacheKey, cost: 16 * 1024)
            return image
        }

        // 3. Prevent duplicate in-flight network requests
        if let existing = inFlightTasks[host] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let image = await downloadFavicon(forHost: host)
            if let image {
                self.memoryCache.setObject(image, forKey: cacheKey, cost: 16 * 1024)
                Task.detached(priority: .utility) {
                    if let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: diskURL, options: .atomic)
                    }
                }
            }
            self.inFlightTasks.removeValue(forKey: host)
            return image
        }

        inFlightTasks[host] = task
        return await task.value
    }

    private func downloadFavicon(forHost host: String) async -> NSImage? {
        // Use privacy-friendly DuckDuckGo Icon Service
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("EasyRSS/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
                return nil
            }
            return Self.downsample(data: data)
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
    @State private var hasLoaded = false

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
            guard showFavicons, !hasLoaded else { return }
            image = await FaviconService.shared.favicon(for: hostOrURL)
            hasLoaded = true
        }
    }
}

// MARK: - High-Performance Downsampling Image Cache & View

@MainActor
final class ImageDownsampleCache {
    static let shared = ImageDownsampleCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyRSS/ImageCache_v1", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskCacheURL = dir

        // Strict 4MB RAM ceiling for all downsampled thumbnails combined
        memoryCache.countLimit = 40
        memoryCache.totalCostLimit = 4 * 1024 * 1024
    }

    func clearMemory() {
        memoryCache.removeAllObjects()
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
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        let nsKey = key as NSString

        // 1. In-memory check
        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        // 2. Disk cache check
        let diskURL = diskFileURL(for: key)
        if fileManager.fileExists(atPath: diskURL.path(percentEncoded: false)),
           let diskData = try? Data(contentsOf: diskURL),
           let downsampled = Self.downsample(data: diskData, maxPixelSize: maxPixelSize) {
            let cost = Int(maxPixelSize * maxPixelSize * 4)
            memoryCache.setObject(downsampled, forKey: nsKey, cost: cost)
            return downsampled
        }

        // 3. Deduplicate in-flight network requests
        if let existing = inFlightTasks[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("EasyRSS/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
                    return nil
                }

                guard let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }

                let cost = Int(maxPixelSize * maxPixelSize * 4)
                self.memoryCache.setObject(downsampled, forKey: nsKey, cost: cost)

                // Save downsampled thumbnail representation to disk
                Task.detached(priority: .utility) {
                    if let tiff = downsampled.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: diskURL, options: .atomic)
                    }
                }

                return downsampled
            } catch {
                return nil
            }
        }

        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)
        return result
    }

    /// High-performance CoreGraphics downsampling: Decodes directly into thumbnail pixels without instantiating full-resolution bitmap in RAM.
    private static func downsample(data: Data, maxPixelSize: CGFloat) -> NSImage? {
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

        return NSImage(cgImage: thumbnailCG, size: NSSize(width: maxPixelSize / 2, height: maxPixelSize / 2))
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

