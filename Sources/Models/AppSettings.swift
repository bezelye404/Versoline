import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case sepia
    case dark
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .sepia: return String(localized: "Sepia")
        case .dark: return String(localized: "Dark")
        case .oled: return String(localized: "OLED Black")
        }
    }

    var backgroundColorCSS: String {
        switch self {
        case .system: return "transparent"
        case .light: return "#ffffff"
        case .sepia: return "#f8f1e3"
        case .dark: return "#1c1c1e"
        case .oled: return "#000000"
        }
    }

    var textColorCSS: String {
        switch self {
        case .system: return "var(--text-color)"
        case .light: return "#1d1d1f"
        case .sepia: return "#433422"
        case .dark: return "#e5e5e7"
        case .oled: return "#d1d1d6"
        }
    }

    var linkColorCSS: String {
        switch self {
        case .system: return "var(--link-color)"
        case .light: return "#0066cc"
        case .sepia: return "#9b4d0e"
        case .dark: return "#6cb4ee"
        case .oled: return "#5ea4ea"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable {
    case system
    case serif
    case sansSerif
    case monospace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .serif: return String(localized: "Serif (New York)")
        case .sansSerif: return String(localized: "Sans-Serif (SF Pro)")
        case .monospace: return String(localized: "Monospace (SF Mono)")
        }
    }

    var cssFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        case .serif:
            return "'New York', Georgia, Cambria, Times, serif"
        case .sansSerif:
            return "'SF Pro Text', -apple-system, Helvetica, Arial, sans-serif"
        case .monospace:
            return "'SF Mono', Menlo, Monaco, Consolas, monospace"
        }
    }
}

enum ReaderLineHeight: String, CaseIterable, Identifiable {
    case compact = "1.5"
    case normal = "1.8"
    case relaxed = "2.1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .normal: return String(localized: "Normal")
        case .relaxed: return String(localized: "Relaxed")
        }
    }
}

struct AppSettingsKeys {
    static let readerTheme = "readerTheme"
    static let readerFontFamily = "readerFontFamily"
    static let readerFontSize = "readerFontSize"
    static let readerLineHeight = "readerLineHeight"
    static let isCompactListMode = "isCompactListMode"
    static let showFavicons = "showFavicons"
    static let enableSingleKeyShortcuts = "enableSingleKeyShortcuts"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let autoReaderMode = "autoReaderMode"
    static let autoCleanupDays = "autoCleanupDays"
    static let mutedKeywords = "mutedKeywords"
}
