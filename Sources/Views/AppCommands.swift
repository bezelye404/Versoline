import SwiftUI

// MARK: - Menu bar commands
//
// Rarely used actions live in the menu bar (where macOS users expect them) instead of crowding the
// window toolbar. The focused window publishes what the commands can do through `AppActions`.

struct AppActions {
    var addFeed: (AddFeedTab) -> Void
    var newFolder: () -> Void
    var manageFolders: () -> Void
    var importOPML: () -> Void
    var exportOPML: () -> Void
    var showReadingInsights: () -> Void
    var showShortcuts: () -> Void
    var showConsole: () -> Void
    var toggleFocusMode: () -> Void
    var showCommandPalette: () -> Void
    var hasFeeds: Bool
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}

struct AppCommands: Commands {

    @FocusedValue(\.appActions) private var actions
    @AppStorage(AppSettingsKeys.isCompactListMode) private var isCompactListMode = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Add Feed...")) { actions?.addFeed(.customURL) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button(String(localized: "New Folder...")) { actions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button(String(localized: "Manage Folders...")) { actions?.manageFolders() }
                .disabled(actions == nil)

            Divider()

            Button(String(localized: "Import OPML...")) { actions?.importOPML() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button(String(localized: "Export OPML...")) { actions?.exportOPML() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions == nil || actions?.hasFeeds == false)
        }

        CommandGroup(after: .toolbar) {
            Toggle(String(localized: "Compact Mode"), isOn: $isCompactListMode)
            Button(String(localized: "Focus Mode")) { actions?.toggleFocusMode() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button(String(localized: "Go to...")) { actions?.showCommandPalette() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions == nil)
            Button(String(localized: "Reading Insights")) { actions?.showReadingInsights() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .help) {
            Button(String(localized: "Keyboard Shortcuts")) { actions?.showShortcuts() }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(actions == nil)
            Button(String(localized: "Developer Console...")) { actions?.showConsole() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}
