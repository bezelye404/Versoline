import Foundation
import Observation

/// A highlight and/or a note on one paragraph (or heading, quote, list) of an article.
struct Annotation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var articleLink: String
    var articleTitle: String
    /// `ArticleBlock.annotationKey` of the text it belongs to.
    var blockKey: String
    /// The start of the text, so notes still read well when the article is gone from the feed.
    var excerpt: String
    var isHighlighted: Bool
    var note: String?
    var createdAt = Date()

    var isEmpty: Bool { !isHighlighted && (note?.isEmpty ?? true) }
}

/// Highlights and notes, kept in `annotations.json` next to the library. Small and read when first needed.
@MainActor
@Observable
final class AnnotationStore {

    static let shared = AnnotationStore()

    private(set) var annotations: [Annotation] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Versoline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("annotations.json")
    }

    // MARK: Reading

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        annotations = (try? decoder.decode([Annotation].self, from: data)) ?? []
    }

    func annotations(forArticle link: String) -> [Annotation] {
        loadIfNeeded()
        return annotations.filter { $0.articleLink == link }
    }

    /// The annotations of an article by the key of the text they belong to.
    func byBlock(forArticle link: String) -> [String: Annotation] {
        Dictionary(annotations(forArticle: link).map { ($0.blockKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func hasAnnotations(forArticle link: String) -> Bool {
        loadIfNeeded()
        return annotations.contains { $0.articleLink == link }
    }

    var annotatedLinks: Set<String> {
        loadIfNeeded()
        return Set(annotations.map(\.articleLink))
    }

    // MARK: Changing

    private func update(link: String, title: String, key: String, excerpt: String, _ change: (inout Annotation) -> Void) {
        loadIfNeeded()
        if let index = annotations.firstIndex(where: { $0.articleLink == link && $0.blockKey == key }) {
            change(&annotations[index])
            if annotations[index].isEmpty { annotations.remove(at: index) }
        } else {
            var created = Annotation(articleLink: link, articleTitle: title, blockKey: key, excerpt: String(excerpt.prefix(200)), isHighlighted: false)
            change(&created)
            if !created.isEmpty { annotations.append(created) }
        }
        scheduleSave()
    }

    func toggleHighlight(link: String, title: String, key: String, excerpt: String) {
        update(link: link, title: title, key: key, excerpt: excerpt) { $0.isHighlighted.toggle() }
    }

    func setNote(_ note: String, link: String, title: String, key: String, excerpt: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        update(link: link, title: title, key: key, excerpt: excerpt) { $0.note = trimmed.isEmpty ? nil : trimmed }
    }

    func remove(link: String, key: String) {
        loadIfNeeded()
        annotations.removeAll { $0.articleLink == link && $0.blockKey == key }
        scheduleSave()
    }

    // MARK: Export

    /// The highlights and notes of an article as Markdown, in the order they were made.
    func markdown(forArticle link: String) -> String {
        let items = annotations(forArticle: link).sorted { $0.createdAt < $1.createdAt }
        guard let first = items.first else { return "" }
        var lines = ["# \(first.articleTitle)", link, ""]
        for item in items {
            let quote = item.excerpt.replacingOccurrences(of: "\n", with: " ")
            lines.append("> \(quote)\(item.excerpt.count >= 200 ? "…" : "")")
            if let note = item.note, !note.isEmpty { lines.append(""); lines.append(note) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = annotations
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Writes immediately (before quitting, and in tests).
    func flush() {
        guard loaded else { return }   // nothing was read or changed: never overwrite the file with an empty list
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(annotations) { try? data.write(to: fileURL, options: .atomic) }
    }
}
