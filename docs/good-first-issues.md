# Good First Issues for Versoline

This document outlines 7 actionable, self-contained starter issues tailored for newcomers and open-source contributors wanting to contribute to **Versoline**.

---

### Issue 1: Add a "Forest" Matte Color Palette
- **Type:** Feature / Enhancement
- **Difficulty:** Easy
- **Description:**  
  Versoline currently provides 10 matte, desaturated palettes (*Slate, Sepia, Sage, Dusk, Monochrome, Nordic, Espresso, Matcha, Bordeaux, Solarized*). We would like to introduce a natural deep evergreen *"Forest"* palette that harmonizes sidebars, accent buttons, and reading backgrounds across light and dark modes.
- **Relevant Files:**
  - `Sources/Models/AppSettings.swift` (define `AppColorPalette.forest` case and color token values)
  - `Sources/Views/Settings/SettingsView.swift` (palette swatch rendering)
- **Acceptance Criteria:**
  - `AppColorPalette.forest` is selectable in Settings and Article View.
  - Colors pass WCAG AA contrast for text legibility in both light and dark macOS system appearance.

---

### Issue 2: Expand Curated Catalog with Science & Space Feeds
- **Type:** Content / Discovery
- **Difficulty:** Very Easy (No Swift knowledge needed)
- **Description:**  
  The built-in feed catalog provides quality discovery feeds across Technology, Design, News, and Podcasts. We want to add a dedicated **"Science & Space"** category featuring reputable, ad-free RSS feeds (e.g. NASA Breaking News, Nature News, ESA, MIT Technology Review).
- **Relevant Files:**
  - `Sources/Resources/curated_feeds.json`
- **Acceptance Criteria:**
  - New category adheres to `CuratedFeedCategory` JSON schema with valid URLs and titles.
  - Feeds resolve successfully and load articles without 404/SSL errors.

---

### Issue 3: Add German (de) and French (fr) Localizations
- **Type:** Internationalization
- **Difficulty:** Easy
- **Description:**  
  Versoline currently ships with English and Turkish localizations. We want to add German and French translations for the primary user interface strings, menus, and keyboard shortcut descriptions.
- **Relevant Files:**
  - `Sources/Resources/en.lproj/Localizable.strings`
  - `Sources/Resources/de.lproj/Localizable.strings` (new)
  - `Sources/Resources/fr.lproj/Localizable.strings` (new)
  - `project.yml` (add localization references)
- **Acceptance Criteria:**
  - All keys present in `en.lproj/Localizable.strings` are accurately translated.
  - Running under German or French system locale displays translated labels without truncation.

---

### Issue 4: Add Shortcut to Mark All Articles as Read (⇧⌘M)
- **Type:** Usability / Keyboard Navigation
- **Difficulty:** Easy
- **Description:**  
  Users can currently mark individual items as read with the <kbd>M</kbd> key. Adding a global keyboard shortcut (<kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>M</kbd>) will allow rapid batch-triaging of the selected feed or smart folder.
- **Relevant Files:**
  - `Sources/Views/ContentView.swift` (add keyboard shortcut modifier to toolbar action)
  - `Sources/Views/KeyboardShortcutsHelpView.swift` (document the shortcut in the help overlay)
- **Acceptance Criteria:**
  - Triggering <kbd>⇧</kbd><kbd>⌘</kbd><kbd>M</kbd> marks all articles in current view as read with haptic feedback.
  - Listed in Keyboard Shortcuts Help modal.

---

### Issue 5: Export Reading Statistics as JSON
- **Type:** Privacy / Data Portability
- **Difficulty:** Medium
- **Description:**  
  Versoline provides native reading statistics rendered via Apple Charts in Settings. In the spirit of data ownership, users should be able to export their aggregated reading session history (daily reads, completion count, saved time) as a clean `.json` file.
- **Relevant Files:**
  - `Sources/Views/Settings/SettingsView.swift` (add Export button to Reading Insights section)
  - `Sources/Services/FeedStore.swift` (add data serialization helper)
- **Acceptance Criteria:**
  - Clicking "Export Reading Stats" opens `NSSavePanel` and writes formatted JSON.
  - Contains timestamps and reading counts without revealing personally identifiable information.

---

### Issue 6: Auto-Hide Mini Player When Playback is Cleared
- **Type:** Polish / UI
- **Difficulty:** Easy
- **Description:**  
  When an episode finishes or the queue is emptied, the docked Mini Player bar currently stays visible showing the last finished track. We should provide a toggle in Settings to automatically collapse the Mini Player when playback has ended.
- **Relevant Files:**
  - `Sources/Models/AppSettings.swift` (add `autoHideMiniPlayer` key)
  - `Sources/Views/MiniPlayerView.swift` (respect setting when playback is idle)
  - `Sources/Views/Settings/SettingsView.swift` (add toggle in Media & Podcasts section)
- **Acceptance Criteria:**
  - Toggle available in Settings under Media section.
  - When enabled, player smoothly animates away after playback completion.

---

### Issue 7: Enhanced OPML Export with Category and Feed Counts
- **Type:** Feature / Enhancement
- **Difficulty:** Easy
- **Description:**  
  Improve `OPMLManager` export output to include standard OPML 2.0 metadata attributes such as `dateCreated`, `dateModified`, and category tags for folder outline elements.
- **Relevant Files:**
  - `Sources/Services/OPMLManager.swift`
- **Acceptance Criteria:**
  - Validated by standard OPML validator tools.
  - Successfully re-imported by Versoline, NetNewsWire, and Feedly.
