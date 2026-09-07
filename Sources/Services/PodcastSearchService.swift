import Foundation
import SwiftUI

@MainActor
@Observable
final class PodcastSearchService {

    static let shared = PodcastSearchService()

    var results: [PodcastSearchResult] = []
    var isSearching: Bool = false
    var errorMessage: String?
    var lastQuery: String = ""

    private var queryCache: [String: [PodcastSearchResult]] = [:]
    private var currentTask: Task<Void, Never>?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            errorMessage = nil
            lastQuery = ""
            return
        }

        if trimmed == lastQuery && !results.isEmpty {
            return
        }

        lastQuery = trimmed

        // Check cache
        if let cached = queryCache[trimmed.lowercased()] {
            self.results = cached
            self.isSearching = false
            self.errorMessage = nil
            return
        }

        currentTask?.cancel()
        isSearching = true
        errorMessage = nil

        currentTask = Task {
            do {
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=podcast&entity=podcast&limit=30") else {
                    self.isSearching = false
                    return
                }

                let (data, response) = try await session.data(from: url)
                guard !Task.isCancelled else { return }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
                    // Filter out any podcasts that lack a valid feed URL
                    let validResults = decoded.results.filter {
                        !$0.feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        ($0.feedURL.hasPrefix("http://") || $0.feedURL.hasPrefix("https://"))
                    }

                    if self.queryCache.count >= 10 {
                        self.queryCache.removeAll()
                    }
                    self.queryCache[trimmed.lowercased()] = validResults
                    self.results = validResults
                    self.isSearching = false
                    self.errorMessage = nil
                    AppLogger.shared.log("Podcast search for '\(trimmed)' returned \(validResults.count) podcasts", level: .info, category: .network)
                } else {
                    self.isSearching = false
                    self.errorMessage = String(localized: "Could not reach podcast search directory.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isSearching = false
                self.errorMessage = error.localizedDescription
                AppLogger.shared.log("Podcast search failed: \(error.localizedDescription)", level: .error, category: .network)
            }
        }
    }

    func clear() {
        currentTask?.cancel()
        results = []
        isSearching = false
        errorMessage = nil
        lastQuery = ""
    }

    func clearCache() {
        queryCache.removeAll()
    }
}
