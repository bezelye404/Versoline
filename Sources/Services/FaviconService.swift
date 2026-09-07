import Foundation
import AppKit
import SwiftUI

@MainActor
final class FaviconService {

    static let shared = FaviconService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyRSS/Favicons", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
        memoryCache.countLimit = 40
        memoryCache.totalCostLimit = 10 * 1024 * 1024 // Max 10MB in RAM
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    func favicon(for hostOrURL: String) async -> NSImage? {
        guard let host = extractHost(from: hostOrURL), !host.isEmpty else { return nil }

        // 1. Memory cache
        let cacheKey = host as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Disk cache
        let diskURL = cacheDirectory.appendingPathComponent("\(host).png")
        if fileManager.fileExists(atPath: diskURL.path(percentEncoded: false)),
           let data = try? Data(contentsOf: diskURL),
           let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // 3. Prevent duplicate in-flight network requests
        if let existing = inFlightTasks[host] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let image = await downloadFavicon(forHost: host)
            if let image {
                self.memoryCache.setObject(image, forKey: cacheKey)
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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
                return nil
            }
            return NSImage(data: data)
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
