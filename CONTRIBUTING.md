# Contributing to Versoline

Thank you for your interest in contributing to **Versoline**! We welcome contributions that align with our core design goals and architectural constraints.

---

## 🧭 Core Principles (Must Not Violate)

1. **Zero Third-Party Dependencies:** Never add Swift Package Manager packages, CocoaPods, or binary frameworks. All functionality must be built using native Apple system frameworks (`SwiftUI`, `WebKit`, `AVFoundation`, `MediaPlayer`, `Network`, `Charts`).
2. **Privacy-First & Offline-First:** No telemetry, tracking SDKs, cloud accounts, or third-party proxy servers. Network requests must connect directly to origin feed hosts.
3. **Local-Only Storage:** User data is persisted exclusively under `~/Library/Application Support/Versoline`.
4. **Lightweight Resource Usage:** Prioritize efficient memory management, downsampled caching, and minimal CPU footprint.

---

## 🛠️ Development Setup

Versoline uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project file. **Never manually commit hand-edited `.xcodeproj` files**; always edit `project.yml` and regenerate:

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Clone your fork
git clone https://github.com/<your-username>/Versoline.git
cd Versoline

# 3. Generate Xcode project
xcodegen generate

# 4. Open in Xcode
open Versoline.xcodeproj
```

### Running Tests

```bash
xcodebuild test -project Versoline.xcodeproj -scheme Versoline -destination 'platform=macOS'
```

---

## 🌿 Contribution Workflow

1. **Fork & Branch:** Create a dedicated branch with a descriptive name (`feat/opml-tags`, `fix/feed-parser-dates`).
2. **Code Style:**
   - Follow standard Swift API Design Guidelines.
   - Use declarative, idiomatic SwiftUI patterns.
   - Avoid force unwrapping (`!`) and force tries (`try!`).
   - Use Swift 6 strict concurrency patterns (`async`/`await`, `@MainActor`, `Sendable`).
3. **Verify Build:** Always verify that both Debug and Release configurations build cleanly:
   ```bash
   xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration Debug build
   xcodebuild -project Versoline.xcodeproj -scheme Versoline -configuration Release build
   ```
4. **Submit PR:** Submit a Pull Request targeting the `main` branch with a clear description of the problem solved.
