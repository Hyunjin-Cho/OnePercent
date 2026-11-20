# OnePercent

> **기준일 (as of):** 2026-11-20 · **Status:** first version (0.1, unreleased). Automated tests pass; the administrator install path has not yet been tried on a real Mac — see [Known gaps](#known-gaps).

A small in-app updater for macOS apps that ship through GitHub Releases. Free, MIT, no third-party code.

**Why the name:** an updater should be the 1% of your app nobody has to think about. It checks quietly, verifies everything, and only swaps the app when the user presses Install.

## What it does

1. **Checks** your repository's latest GitHub release — on a schedule you choose, or when the user asks. Background checks only *tell* the user; nothing is downloaded until they press Install.
2. **Downloads** the release ZIP over HTTPS (allowed hosts only, size-limited while receiving, SHA-256 compared with GitHub's published digest when there is one).
3. **Inspects the ZIP before unpacking** — it reads the ZIP's own listing and refuses paths outside the app, entries under symbolic links, comments, ZIP64 and oversized archives — then unpacks with `ditto` while watching bytes, item count and time on disk.
4. **Verifies the app**, and installs only if every check passes:
   - a real app folder, exactly `<YourApp>.app` at the top level, no links pointing outside it;
   - your bundle ID;
   - an Apple-issued **Developer ID** certificate of **your Team**, checked twice (Security.framework with strict flags, and `codesign --deep --strict`), with one code requirement;
   - Apple **notarization** (`spctl`);
   - a higher version **and** a higher build number than the running app;
   - exactly the version that was announced.
5. **Replaces the app without deleting it first.** A user-owned app is copied next to itself, re-checked, and swapped in one step. An app the user cannot write asks for an administrator password; the copy is re-checked again with elevated rights and the old app is kept as a backup until the new one is in place.
6. **Reopens** the new version, and tells your app on the next launch that it was just updated.

Leftovers of an interrupted update (force quit, power loss) are removed at the next launch.

## Requirements

- macOS 14 or later, Swift 6 toolchain (Xcode 16 or later).
- Releases on GitHub, signed with **Developer ID** and **notarized**.
- Each release: a tag that is your version (for example `1.2` or `v1.2`), and one ZIP asset named `<YourApp>_<tag>.zip`.

## Add it

Swift Package Manager:

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", branch: "main")
```

then add `"OnePercent"` to your app target's dependencies.

## Use it

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp",          // owner/name on GitHub
    teamIdentifier: "ABCDE12345",       // your Developer ID Team
    bundleIdentifier: "com.example.yourapp",
    appName: "YourApp"))                // the ZIP holds YourApp.app

// At launch:
if let version = updater.noteLaunch() {
    // First launch after updating to `version` — say so, if you like:
    // OnePercentText.updated(to: version)
}
updater.onUpdateAvailable = { update in
    // Show your own notice. Do not install from here.
}
updater.installGuard = {
    timer.isRunning ? "Stop the timer first." : nil   // a reason to refuse, or nil
}
updater.startAutomaticChecks()

// In your settings:
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()
updater.cancel()                         // while downloading or verifying
```

`OnePercentUpdater` is `@Observable`. For your UI, read `updater.presentation` — which line to show, whether to show the Install or Cancel button, and the last error — and use `OnePercentText` for ready-made strings.

## Making a release

```sh
# 1. Build, sign with Developer ID, notarize and staple YourApp.app as usual.
#    Raise both CFBundleShortVersionString and CFBundleVersion.
# 2. Zip it with the parent folder kept:
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. Check it with the same code your users' Macs will run:
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp
# 4. Publish a GitHub release with tag 1.2 and attach YourApp_1.2.zip.
```

Do not make the ZIP with Finder's Compress — it can add a `__MACOSX` folder, which is refused.

## Configuration

Only the first four are required.

| Setting | Default | Meaning |
|---|---|---|
| `repository` | — | GitHub `owner/name`. Only the latest non-draft, non-pre-release release is used. |
| `teamIdentifier` | — | Your 10-character Team ID. A download signed by anyone else is refused. |
| `bundleIdentifier` | — | The bundle ID the download must have. |
| `appName` | — | Your app's name without `.app`. |
| `versionScheme` | `.numeric` | How versions are read and ordered (below). |
| `tagPrefix` | `""` | Text before the version in tags, such as `"v"`. |
| `assetName` | `<appName>_<tag>.zip` | The asset file name for a tag. |
| `versionSuffixInfoKey` | none | An Info.plist key appended to `CFBundleShortVersionString` (for example `_hotfix1`). |
| `requireBuildIncrease` | `true` | Also require a higher `CFBundleVersion`. |
| `schedule` | `.monthly` | `.monthly`, `.weekly`, `.daily`, `.every(seconds)` (at least an hour) or `.manual`. |
| `automaticChecksByDefault` | `true` | Background checks before the user touches the switch. |
| `installLocation` | `.inPlace` | `.inPlace` replaces the running app wherever it is; `.applicationsFolder` only from `/Applications/<appName>.app`. |
| `defaultsKeyPrefix` | `"OnePercent."` | Prefix of the stored keys. |
| `userAgent` | `<appName>/<version>` | The `User-Agent` header. |
| `limits` | 500 MiB download; 50,000 items, 2 GiB, 300 s unpacking | Small apps may tighten these. |

### Version schemes

- `.numeric` — `1`, `1.0`, `1.2.3`, `2026.11.17`. Missing parts count as zero (`1.0` = `1.0.0`). Parts compare as numbers (`1.10` > `1.9`).
- `.calendar()` — `YYYY.MM.DD` with an optional numbered hotfix suffix: `2026.11.17_hotfix2`.
- Your own: `VersionScheme(name: "build") { text in /* return [Int] or nil */ }`.

A version the scheme cannot read is never treated as newer.

## Languages

All messages come in 29 languages and follow your app's language: Czech, Danish, German, Greek, English, Spanish, Finnish, Filipino, French, Hungarian, Indonesian, Italian, Japanese, Korean, Malay, Norwegian, Dutch, Polish, Portuguese (Brazil and Portugal), Romanian, Russian, Swedish, Thai, Turkish, Ukrainian, Vietnamese and Chinese (Simplified and Traditional). The Korean text is the original; the others were written from it.

## What it sends

Only HTTPS `GET` requests to GitHub (`api.github.com` for the release, `github.com` and its asset hosts for the ZIP). OnePercent sets three headers: `Accept`, `User-Agent` and `Accept-Language: en` — fixed, so your user's language list is not sent. No cookies, no disk cache, no identifiers, nothing about the user's data. GitHub sees the request as it sees any web request (including the IP address).

## Stored values

In `UserDefaults` (or a store you pass): whether background checks are on, the last successful check, the latest version seen, the last announced version and the last launched version. `OnePercentUpdater.storedKeys(configuration:)` lists every key, so your app can remove them when it resets itself.

## Known gaps

- **The administrator path has not been tried on a real Mac yet.** It is fully tested with stand-in commands, but not with a real password prompt. [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md) is the checklist.
- While the administrator copy runs, the app's main thread waits (the system password prompt runs through `NSAppleScript`, which must stay on the main thread).
- The new app opens before the old one quits, so for a moment both may be running.
- No delta updates, no staged roll-out, no separate EdDSA signature. Authenticity rests on Developer ID, notarization and the announced version.

## Development

```sh
swift test
```

Tests never touch the network, `/Applications` or your preferences. They build fake apps in a temporary folder and run the real `ditto`, the real unpacking guards and the real administrator shell script with stand-in commands.

## Credits

OnePercent began as the updater inside HaneulKeyboard and was generalized here by the same author. The overall flow was first modelled on [exelban/stats](https://github.com/exelban/stats) (MIT). Ideas — not code — were also taken from [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT), [mxcl/AppUpdater](https://github.com/mxcl/AppUpdater) (Unlicense) and [Squirrel.Mac](https://github.com/Squirrel/Squirrel.Mac) (MIT).

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Hyunjin Cho.
