# Contributing to easyRSS

Thank you for your interest in contributing to easyRSS!

## Principles

1. **Native First**: Prioritize macOS native paradigms (AppKit/SwiftUI) and system styling.
2. **Minimal & Lightweight**: Avoid unnecessary dependencies, complex third-party frameworks, and visual clutter (excessive emojis, redundant UI controls).
3. **Privacy & Offline First**: easyRSS is a local desktop reader. Features must not depend on cloud tracking or mandatory third-party accounts.

## Pull Requests

1. Branch out from the active development branch rather than `main`.
2. Ensure your changes compile cleanly on macOS 14.0+ without warnings or deprecated APIs.
3. Keep commits focused, descriptive, and atomic.
4. Verify that existing feed parsing and reader rendering remain completely isolated from live browser content blockers.

## Reporting Issues

When reporting an issue or suggesting a feature, please include:
- Your macOS version.
- Detailed steps to reproduce (or sample RSS/Atom/JSON feed URLs).
- Expected vs actual behavior.
