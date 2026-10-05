import Foundation
import os.log

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    public var systemImage: String {
        switch self {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon.fill"
        }
    }
}

public enum LogCategory: String, Codable, CaseIterable, Sendable {
    case network = "Network"
    case parser = "Parser"
    case storage = "Storage"
    case ui = "UI"
    case system = "System"

    public var systemImage: String {
        switch self {
        case .network: return "network"
        case .parser: return "doc.text.magnifyingglass"
        case .storage: return "externaldrive"
        case .ui: return "macwindow"
        case .system: return "gearshape"
        }
    }
}

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let details: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }
}

/// Removes data from log text that must not leave the machine when a user copies or exports the
/// console to share it (for example in a bug report): credentials and query strings inside URLs
/// (private feeds often carry an access token there) and the macOS account name in file paths.
/// Logs shown in the in-app console stay unredacted; only copy/export go through this.
public enum LogRedactor {
    private static let rules: [(regex: NSRegularExpression, template: String)] = [
        (#"(?<=://)[^/@\s"']+@"#, ""),            // credentials in URLs
        (#"\?[^\s"')<>]+"#, "?…"),                // query strings
        (#"/Users/[^/\s"']+"#, "/Users/~"),       // macOS account name
    ].compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }

    public static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }
}

@MainActor
@Observable
public final class AppLogger {

    public static let shared = AppLogger()

    public private(set) var entries: [LogEntry] = []
    public var maxEntries: Int = 200

    private let osLog = Logger(subsystem: AppInfo.identifier, category: "App")

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private init() {
        log("AppLogger initialized", level: .info, category: .system)
    }

    public func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .system,
        details: String? = nil
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            details: details
        )

        // Write to OSLog
        switch level {
        case .debug:
            osLog.debug("[\(category.rawValue)] \(message)")
        case .info:
            osLog.info("[\(category.rawValue)] \(message)")
        case .warning:
            osLog.warning("[\(category.rawValue)] \(message)")
        case .error:
            osLog.error("[\(category.rawValue)] \(message)")
        }

        // Write to in-memory buffer
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
        log("Console logs cleared", level: .info, category: .system)
    }

    /// Text for "Copy" and "Export". Redacted, see `LogRedactor`.
    public func exportFormattedLogs() -> String {
        entries.map { entry in
            let timeStr = Self.timeFormatter.string(from: entry.timestamp)
            var line = "[\(timeStr)] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(LogRedactor.redact(entry.message))"
            if let details = entry.details, !details.isEmpty {
                line += "\n    Details: \(LogRedactor.redact(details))"
            }
            return line
        }.joined(separator: "\n")
    }
}
