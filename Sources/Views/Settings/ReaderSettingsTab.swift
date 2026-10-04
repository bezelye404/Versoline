import SwiftUI
import AppKit
import WebKit

struct ReaderSettingsTab: View {

    @AppStorage(AppSettingsKeys.defaultReadingMode) private var defaultReadingModeRaw = ReadingViewMode.reader.rawValue
    @AppStorage(AppSettingsKeys.readerTheme) private var readerThemeRaw = ReaderTheme.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontFamily) private var readerFontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage(AppSettingsKeys.readerFontSize) private var readerFontSize = 16
    @AppStorage(AppSettingsKeys.readerLineHeight) private var readerLineHeightRaw = ReaderLineHeight.normal.rawValue
    @AppStorage(AppSettingsKeys.autoReaderMode) private var autoReaderMode = false
    @AppStorage(AppSettingsKeys.isBionicReadingEnabled) private var isBionicReadingEnabled = false

    var body: some View {
        Form {
            Section("Default Mode") {
                Picker("Default Article View:", selection: $defaultReadingModeRaw) {
                    ForEach(ReadingViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                Text("Select whether articles initially open in Reader Mode or Web Browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme:", selection: $readerThemeRaw) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }

                Picker("Font Family:", selection: $readerFontFamilyRaw) {
                    ForEach(ReaderFontFamily.allCases) { font in
                        Text(font.title).tag(font.rawValue)
                    }
                }

                Picker("Line Spacing:", selection: $readerLineHeightRaw) {
                    ForEach(ReaderLineHeight.allCases) { lh in
                        Text(lh.title).tag(lh.rawValue)
                    }
                }

                Stepper(value: $readerFontSize, in: 12...32, step: 2) {
                    HStack {
                        Text("Font Size:")
                        Text("\(readerFontSize) px")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Reading Focus") {
                Toggle("Bionic Reading", isOn: $isBionicReadingEnabled)
                Text("Emboldens the initial characters of words to guide visual fixation and enhance reading flow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automation") {
                Toggle("Automatically Open in Reader Mode", isOn: $autoReaderMode)
                Text("Automatically extracts full article body for feeds that only provide short summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

// MARK: - 3. Shortcuts Tab
