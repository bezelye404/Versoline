# Versoline Release Guide

This document describes the step-by-step procedure for building, verifying, and publishing a new release of **Versoline**.

---

## 📋 Release Checklist

### 1. Pre-Release Verification

- [ ] Ensure all intended PRs are merged into `main`.
- [ ] Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- [ ] Update `CHANGELOG.md` with new features, fixes, and release date under `[X.Y.Z]`.
- [ ] Regenerate Xcode project and run tests:

  ```bash
  xcodegen generate
  xcodebuild test -project Versoline.xcodeproj -scheme Versoline -destination 'platform=macOS'
  ```

### 2. Build Release DMG

Run the automated packaging script:

```bash
./scripts/build-dmg.sh <VERSION>
```

*Example:* `./scripts/build-dmg.sh 0.3.0`  
This produces `dist/Versoline-<VERSION>.dmg`.

### 3. Verify the Release Binary

Run the verification script to check SHA-256 and signatures:

```bash
./scripts/verify-release.sh dist/Versoline-<VERSION>.dmg
```

### 4. Git Tag & GitHub Release

- Tag the commit on `main`:

  ```bash
  git tag -a v<VERSION> -m "Release v<VERSION>"
  git push origin v<VERSION>
  ```

- Create the GitHub Release using `gh`:

  ```bash
  gh release create v<VERSION> dist/Versoline-<VERSION>.dmg \
    --title "Versoline v<VERSION>" \
    --notes-file docs/release-<VERSION>.md
  ```
