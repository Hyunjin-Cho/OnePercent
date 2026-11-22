# Changelog

> **기준일:** 2026-11-22 · Versions are Git tags (SwiftPM reads them directly). Newest first.

## 0.1.2 — 2026-11-22

Fixes from the code review of 2026-11-22 (claude-opus-5-5-review-2255).

### Fixed
- An app whose name has a composed character (é, Hangul, kana with dakuten) could never install an update: ZIPs from macOS hold the folder name decomposed (NFD) and the listing check compared it byte by byte with `appName` (usually NFC). The app-folder part is now compared in one normalization. ([#18](https://github.com/Hyunjin-Cho/OnePercent/issues/18))
- `problems` reports an `appName` with characters GitHub changes in uploaded file names when no `assetName` is set — measured: `Café_1.6.zip` → `Cafe_1.6.zip`, `닦아_1.6.zip` → `_1.6.zip`. ([#18](https://github.com/Hyunjin-Cho/OnePercent/issues/18))
- Another launch of the app during a user-path swap could delete the staging copy (it carried the ZIP's old modification time) and fail the update. The staging is now a fresh folder holding the copy. ([#19](https://github.com/Hyunjin-Cho/OnePercent/issues/19))
- A user's Check Now while the app holds the shared `OperationGate` now shows `.busy` instead of nothing. ([#22](https://github.com/Hyunjin-Cho/OnePercent/issues/22))
- A broken `versionSuffixInfoKey` value no longer falls back to the version without the suffix (which offered the running hotfix as new); it is reported as `badConfiguration`, naming the key. ([#23](https://github.com/Hyunjin-Cho/OnePercent/issues/23))

### Tools
- `onepercent-check` takes the app's own settings: `--asset-name`, `--no-build-increase`, `--max-asset-mb`, `--max-entries`, `--max-unpacked-mb`, `--unpack-seconds`; the release check also compares the ZIP's size with `limits.maxAssetBytes`. ([#20](https://github.com/Hyunjin-Cho/OnePercent/issues/20))
- `TestApp/make-app.sh` validates its arguments before removing anything. ([#21](https://github.com/Hyunjin-Cho/OnePercent/issues/21))

### Project
- `TestApp/`: **OnePercentTestApp** and `make-app.sh` for the real-Mac cases — driven by buttons or launch arguments, every step logged. Results are in `docs/MANUAL-TEST.md`: cases 1 and 5–13 pass on macOS 27.2.1, including a real update with a notarized build (case 1) and a force quit in the middle of replacing that left the old app intact (case 7). The administrator path (cases 2–4b) still needs a person. ([#15](https://github.com/Hyunjin-Cho/OnePercent/issues/15))
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
