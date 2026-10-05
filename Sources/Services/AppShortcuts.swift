import AppIntents

// Two actions for the Shortcuts app and Spotlight: refresh the feeds and read the unread count. They run inside the app
// (Versoline opens if it is not running), use the same library the window shows and send nothing anywhere.

extension FeedStore {
    /// The store of the running app, for actions that start outside a window. Set once the first window appears.
    @MainActor static weak var current: FeedStore?

    /// Waits a few seconds for the app to finish starting when an action launched it.
    @MainActor static func whenReady() async -> FeedStore? {
        for _ in 0..<50 {
            if let current { return current }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

struct RefreshFeedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Feeds"
    static let description = IntentDescription("Checks all your feeds for new articles.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = await FeedStore.whenReady() else {
            return .result(dialog: "Versoline could not start. Try again.")
        }
        await store.refreshAllFeeds(force: true)
        return .result(dialog: "Feeds refreshed. \(store.totalUnreadCount()) unread.")
    }
}

struct UnreadCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Unread Count"
    static let description = IntentDescription("Returns how many articles are unread.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let store = await FeedStore.whenReady() else { return .result(value: 0) }
        return .result(value: store.totalUnreadCount())
    }
}

struct VersolineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshFeedsIntent(),
            phrases: ["Refresh \(.applicationName)", "Refresh feeds in \(.applicationName)"],
            shortTitle: "Refresh Feeds",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: UnreadCountIntent(),
            phrases: ["Unread count in \(.applicationName)"],
            shortTitle: "Unread Count",
            systemImageName: "envelope.badge"
        )
    }
}
