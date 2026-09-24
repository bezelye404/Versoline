# Homebrew Cask Formula Draft for Versoline

Due to current Homebrew policies, official `homebrew/cask` requires Apple Developer ID codesigning and Apple Notarization. For ad-hoc signed open-source software, distributing via a personal tap (`bezelye404/homebrew-tap`) is the recommended and standard approach.

---

## 🍺 How Users Install via Tap

```bash
# Add personal tap and install Versoline
brew tap bezelye404/tap
brew install --cask versoline

# Or in a single command:
brew install --cask bezelye404/tap/versoline
```

---

## 📝 Cask Formula: `Casks/versoline.rb`

Place this file inside your tap repository under `Casks/versoline.rb`:

```ruby
cask "versoline" do
  version "0.3.0"
  sha256 "PLACEHOLDER_SHA256_HASH_HERE"

  url "https://github.com/bezelye404/Versoline/releases/download/v#{version}/Versoline-#{version}.dmg"
  name "Versoline"
  desc "Private, zero-dependency RSS reader for macOS (formerly easyRSS)"
  homepage "https://github.com/bezelye404/Versoline"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "Versoline.app"

  postflight do
    # Remove quarantine attribute on install for ad-hoc open-source app
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Versoline.app"]
  end

  zap trash: [
    "~/Library/Application Support/Versoline",
    "~/Library/Application Support/EasyRSS",
    "~/Library/Containers/com.bezelye.Versoline",
    "~/Library/Containers/com.bezelye.EasyRSS",
    "~/Library/Preferences/com.bezelye.Versoline.plist",
    "~/Library/Preferences/com.bezelye.EasyRSS.plist",
    "~/Library/Saved Application State/com.bezelye.Versoline.savedState",
  ]
end
```

---

## 📋 Steps to Create the Tap Repository

1. Create a new public repository on GitHub named: `bezelye404/homebrew-tap`
2. Create directory `Casks/` in that repo.
3. Generate the SHA-256 hash of your uploaded `Versoline-0.3.0.dmg`:
   ```bash
   shasum -a 256 dist/Versoline-0.3.0.dmg
   ```
4. Replace `PLACEHOLDER_SHA256_HASH_HERE` in `Casks/versoline.rb` with the actual hash and commit.
