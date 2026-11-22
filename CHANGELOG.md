# Changelog

> **기준일:** 2026-11-22 · Versions are Git tags (SwiftPM reads them directly). Newest first.

## Unreleased

### Project
- `TestApp/`: **OnePercentTestApp** and `make-app.sh` for the real-Mac cases — driven by buttons or launch arguments, every step logged. First results (cases 5, 6, 9–13 pass) are in `docs/MANUAL-TEST.md`. ([#15](https://github.com/Hyunjin-Cho/OnePercent/issues/15))
- The GitHub Actions workflow is removed — owner decision 2026-11-22: OnePercent goes without CI. The test fixes from [#11](https://github.com/Hyunjin-Cho/OnePercent/pull/11) stay; run `swift test` (and `swift test --build-system native`) by hand. ([#13](https://github.com/Hyunjin-Cho/OnePercent/issues/13))

## 0.1.1 — 2026-11-22

### Fixed
- A running version the version scheme cannot read (for example `1.0-beta` with `.numeric`) stays reported as `badConfiguration`. Before, the first check cleared the error and stored an "up to date" check, so with the monthly schedule it stayed hidden until next month. ([#6](https://github.com/Hyunjin-Cho/OnePercent/issues/6))

### Documentation
- Requirements: a **public** repository (OnePercent asks without signing in) and **no App Sandbox** (measured: a sandboxed app cannot copy itself into its own folder). ([#8](https://github.com/Hyunjin-Cho/OnePercent/issues/8))
- An `.app` put together by hand from a SwiftPM executable must copy `OnePercent_OnePercent.bundle` into `Contents/Resources`. ([#8](https://github.com/Hyunjin-Cho/OnePercent/issues/8))
- The Settings example calls `checkNow(showNotice: false)`. ([#8](https://github.com/Hyunjin-Cho/OnePercent/issues/8))

### Project
- The tests run on GitHub for every pull request: macOS 26 with the image's default Xcode, and macOS 15 with Xcode 16.0 (Swift 6.0) — the oldest the README promises, now checked rather than assumed. ([#10](https://github.com/Hyunjin-Cho/OnePercent/issues/10))
- The tests themselves now build with Swift 6.0, and no longer depend on the case of `.lproj` folder names (SwiftPM's native build system stores `pt-br.lproj`; Swift Build and Xcode keep `pt-BR.lproj` — the chosen language is the same). The library code did not change. ([#11](https://github.com/Hyunjin-Cho/OnePercent/pull/11))

## 0.1.0 — 2026-11-20

- First version: check, verify and install GitHub releases in-app. ([#1](https://github.com/Hyunjin-Cho/OnePercent/pull/1))
- `OnePercentUpdater.removeLeftovers(configuration:installedApp:olderThan:)` for an app's own uninstaller. ([#2](https://github.com/Hyunjin-Cho/OnePercent/pull/2))
