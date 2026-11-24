# Changelog

> **기준일:** 2026-11-24 · Versions are Git tags (SwiftPM reads them directly). Newest first.

## 0.2.1 — 2026-11-24

Fixes from the code review of 0.2.0 (Fable 5.2).

### Fixed
- 0.2.0 also looked for its resource bundle in the folder **holding** the app (for example `/Applications`, which admin-group programs can write to without a password) — outside the signed app. An app without its own bundle then showed text from a bundle planted next to it, and a planted format with extra `%@` crashed it. OnePercent now looks inside the app only (`Contents/Resources`, the app's top folder, the executable's folder; a separate test bundle or framework adds its own folder), and never uses a format whose placeholders do not fit the values passed — English instead. The README said "next to the app"; it is the app's top folder. ([#49](https://github.com/Hyunjin-Cho/OnePercent/issues/49))
- A version refused on this Mac is announced again (`onUpdateAvailable`) once macOS is new enough — the first announcement came when it could not open here. ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50))
- `*.` entries in `allowedHosts` match only host-name characters: `URL.host` decodes percent escapes, so `evil.example%2F.githubusercontent.com` used to pass (the connection itself failed). ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50))
- `OnePercentUpdateSection`: Check Now right after an update now shows its result ("You're up to date." under "Updated to …"). ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50))

### Tools
- `onepercent-check` warns when the app has no readable `LSMinimumSystemVersion` — then no Mac is ever refused. ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50))

### Documentation
- 0.2.0's "What apps must change" missed three items, now listed there. README "Once a version is out" adds `appName` and `versionScheme`. Values OnePercent stores are trusted: same-user code could write an `incompatibleUpdate` record and hide a version on this Mac — but such code can also replace an app the user can write, so the store is not a security boundary (owner decision 2026-11-24). ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50))

## 0.2.0 — 2026-11-24

### What apps must change
- `OnePercentError` has two new cases, `requiresNewerSystem(version:minimum:running:)` and `unsupportedProcessor(version:)` — an exhaustive `switch` over it needs them.
- `OnePercentText.error(_:)` and `UpdateStatusPresentation.errorText` now end with a code in brackets, for example `… (rateLimited)`. `errorDescription` is unchanged.
- `allowedHosts` entries are validated: a custom entry that is not a lowercase host name (or `*.` and a name with at least two labels) is reported in `problems`, and the updater refuses to run until it is fixed.
- The README pin is `.upToNextMinor(from: "0.2.0")`.
- Listed after the 0.2.0 review ([#50](https://github.com/Hyunjin-Cho/OnePercent/issues/50)): a custom `OnePercentStore` must store a dictionary (`incompatibleUpdate`: `[String: Any]` holding `[Int]`), not only Bool, Date and String; `phase` can be `.upToDate` while `lastError` says the newer version cannot run on this Mac — do not show "You're up to date." then; `githubHosts` now holds `*.githubusercontent.com` instead of the two CDN names.

### Added
- An update this Mac cannot open is refused before anything is replaced: the new version's `LSMinimumSystemVersion` against this Mac's macOS, and its processors against what can run here (an Intel app under Rosetta keeps working as now). The version is remembered (new stored key `incompatibleUpdate`), so the install button goes away — also after a relaunch — until macOS is new enough or a newer version comes out. This protects users only from versions *after* one that has it: ship 0.2.0 before raising the minimum macOS or dropping a processor. ([#33](https://github.com/Hyunjin-Cho/OnePercent/issues/33))
- `OnePercentUpdateSection(updater:showsAutomaticChecksSwitch:)` — a ready-made SwiftUI update section in the system's own look. ([#37](https://github.com/Hyunjin-Cho/OnePercent/issues/37))
- `OnePercentError.diagnosticCode`, `VerificationFailure.code`, `ArchiveProblem.code`; shown errors carry the code, so a screenshot in any language can be read. ([#35](https://github.com/Hyunjin-Cho/OnePercent/issues/35))

### Fixed
- An app whose resource bundle is not where SwiftPM's native build system looks (an `.app` put together by hand with the bundle in `Contents/Resources`, as the README said) no longer crashes on users' Macs the first time it shows text. OnePercent finds its bundle itself (`Contents/Resources`, next to the app, next to the executable, in a framework) and falls back to English built into the code. ([#34](https://github.com/Hyunjin-Cho/OnePercent/issues/34))
- The staging copy next to the app is named `<App>.app.incoming`, not `<App>.app`. macOS registered the `.app` copy with Launch Services and kept the registration after the folder was gone — measured on macOS 27.2.1: the `/Applications` watcher registers a hidden `.app` within seconds, and `replaceItemAt` registers the copy's path when it replaces a large registered app. Neither happens with the new name; the re-check and the installed app's name are unchanged. No effect on opening the app or its URL schemes was found — the registrations were clutter. ([#31](https://github.com/Hyunjin-Cho/OnePercent/issues/31))
- Redirects may reach any host below `githubusercontent.com` (`*.` entries in `allowedHosts`), so a new GitHub asset host does not cut off apps already shipped. The asset address itself must still be `github.com/<repository>/releases/download/…`. ([#36](https://github.com/Hyunjin-Cho/OnePercent/issues/36))

### Tools
- `onepercent-check --published` fetches the latest release exactly the way apps do and checks what they will get; the two GitHub requests are shared with the updater (`GitHubReleases`). It also warns about AppleDouble (`._`) entries — measured: without `ditto --norsrc` a test-app ZIP had 70, and `unzip` then broke the app's signature — and prints the app's minimum macOS and processors. ([#38](https://github.com/Hyunjin-Cho/OnePercent/issues/38))

### Documentation
- README: ZIPs are made with `ditto -c -k --norsrc --keepParent`; a new section on what must never change once a version is out; the resource bundle note is corrected; `--published`. `TestApp/make-app.sh` and `docs/MANUAL-TEST.md` use `--norsrc` too. ([#39](https://github.com/Hyunjin-Cho/OnePercent/issues/39))

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
