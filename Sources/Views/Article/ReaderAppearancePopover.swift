import SwiftUI

/// "Aa" popover of the article toolbar: everything about how the reader looks, in one place.
struct ReaderAppearancePopover: View {

    @AppStorage(AppSettingsKeys.readerFontSize) private var fontSize = 16
    @AppStorage(AppSettingsKeys.readerTheme) private var themeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var fontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerLineHeight) private var lineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.isBionicReadingEnabled) private var isBionicReadingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    if fontSize > 12 { fontSize -= 2 }
                } label: {
                    Text("A").font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 24)
                }
                .help(String(localized: "Smaller Font"))
                .disabled(fontSize <= 12)

                Text("\(fontSize) px")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48)
                    .animation(AppAnimation.quickFeedback, value: fontSize)

                Button {
                    if fontSize < 32 { fontSize += 2 }
                } label: {
                    Text("A").font(.system(size: 18, weight: .medium))
                        .frame(width: 28, height: 24)
                }
                .help(String(localized: "Larger Font"))
                .disabled(fontSize >= 32)
            }
            .frame(maxWidth: .infinity)

            Picker(String(localized: "Theme"), selection: $themeRaw) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }

            Picker(String(localized: "Font Family"), selection: $fontFamilyRaw) {
                ForEach(ReaderFontFamily.allCases) { font in
                    Text(font.title).tag(font.rawValue)
                }
            }

            Picker(String(localized: "Line Spacing"), selection: $lineHeightRaw) {
                ForEach(ReaderLineHeight.allCases) { spacing in
                    Text(spacing.title).tag(spacing.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle(String(localized: "Bionic Reading"), isOn: $isBionicReadingEnabled)
        }
        .padding(16)
        .frame(width: 280)
    }
}
