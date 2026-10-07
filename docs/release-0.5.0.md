# Versoline 0.5.0

A calendar, a desktop widget, a language setting and Homebrew.

## What is new

- **Calendar.** A month view that shows how many articles arrived on each day and which days have bookmarks. Pick a day to see its articles, or only its bookmarks. It covers the articles still stored on your Mac.
- **Widget** in three sizes: the unread count and the newest headlines, top stories first. It follows the app's color palette, or you can choose one of the ten palettes for each widget (Edit Widget). Tapping a headline opens the article in Versoline. The widget never uses the network; the app writes one small file when what the widget shows changes.
- **Language.** Settings > General can pin the app to English or Turkish, or follow the system.
- **Homebrew.** `brew install --cask bezelye404/versoline/versoline`. The tap updates itself when a release is published.

## Notes

- The widget's data is the one thing stored outside `~/Library/Application Support/Versoline`: a single small file in the app group container (`~/Library/Group Containers/group.com.bezelye.Versoline`). Factory reset empties it.
- Requires macOS 15 (Sequoia) or later. Apple silicon and Intel.
- The app is signed ad hoc. If macOS says the developer cannot be verified, right-click the app and choose **Open**, or run `xattr -cr /Applications/Versoline.app`. Installing with Homebrew avoids this.
- Full list of changes: [CHANGELOG](../CHANGELOG.md).
