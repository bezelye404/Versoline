import SwiftUI

// The same palette the web-based reader uses, as SwiftUI colours. `.system` returns nil so the reader follows
// the app's own appearance instead of painting over it.

extension ReaderTheme {
    var nativeBackground: Color? { Color(readerHex: backgroundColorCSS) }
    var nativeText: Color? { Color(readerHex: textColorCSS) }
    var nativeLink: Color? { Color(readerHex: linkColorCSS) }
}

private extension Color {
    /// "#rrggbb" only; anything else (transparent, CSS variables) is nil.
    init?(readerHex value: String) {
        guard value.hasPrefix("#"), value.count == 7, let rgb = UInt32(value.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension ReaderFontFamily {
    var nativeDesign: Font.Design {
        switch self {
        case .system, .sansSerif: return .default
        case .serif: return .serif
        case .monospace: return .monospaced
        }
    }
}
