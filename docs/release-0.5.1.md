# Versoline 0.5.1

Fixes a permission prompt in 0.5.0 and adds a way to take back what the app can reach.

## Fixed

- **macOS no longer asks "Versoline wants to access data from other apps" every time the app opens.** Version 0.5.0 shared the widget's data through an app group, which macOS questions on every launch for an app that is signed ad hoc. The app now writes the widget's snapshot (the unread count and a few headlines) to `~/Library/Application Support/Versoline Widget`, a single folder that only the app and its widget are allowed to reach. If you answered the prompt with "Don't Allow" in 0.5.0, the widget works again after this update.

## What is new

- **Reset Permissions & Access** (Settings > Storage): turns off the Dock badge, menu bar icon, Spotlight bookmarks, widget data and nearby sync, and forgets your paired Macs. Your feeds, articles and other settings stay. macOS keeps its own record of permissions such as local network access, and an app cannot clear that from inside its sandbox, so the same section opens Privacy & Security and copies the `tccutil` command for you.
- **Show Articles in the Widget** (Settings > General): turn it off to delete the widget's data file and leave the widget empty.

## Notes

- Requires macOS 15 (Sequoia) or later. Apple silicon and Intel.
- The app is signed ad hoc. If macOS says the developer cannot be verified, right-click the app and choose **Open**, or run `xattr -cr /Applications/Versoline.app`. Installing with Homebrew avoids this.
- The old, empty widget folder from 0.5.0 (`~/Library/Group Containers/group.com.bezelye.Versoline`) can be deleted.
- Full list of changes: [CHANGELOG](../CHANGELOG.md).
