# OnePercent

[English](README.md) · [한국어](README.ko.md)

> **As of:** 2026-11-22 · 0.1.0 · Installs that need an administrator password are off by default until tried on a real Mac.

A small in-app updater for macOS apps that ship through GitHub Releases. It downloads only when the user presses Install, and replaces the app only if the download passes every check: your Team's Developer ID signature, Apple notarization, bundle ID, and a higher version and build number.

## Requirements

- macOS 14 or later, Swift 6 (Xcode 16 or later).
- An app signed with **Developer ID** and **notarized**.
- Each release: a tag equal to the version (`1.2` — for `v1.2` set `tagPrefix: "v"`), one ZIP named `<YourApp>_<tag>.zip`, and a raised `CFBundleVersion`.
- While an update reopens your app, `applicationShouldTerminate` must not return `.terminateCancel`.

## Add it

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.0"))
```

## Use it

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp", teamIdentifier: "ABCDE12345",
    bundleIdentifier: "com.example.yourapp", appName: "YourApp"))

updater.noteLaunch()   // once at launch; returns the new version right after an update
updater.onUpdateAvailable = { update in /* show your own notice; do not install here */ }
updater.willRelaunch = { /* save here — the new copy starts before applicationWillTerminate */ }
updater.startAutomaticChecks()

// Settings: await updater.checkNow() · Install button: await updater.installAvailableUpdate()
```

Build your UI from `updater.presentation` and `OnePercentText` (29 languages). Other settings are documented in [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift).

## Making a release

```sh
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip   # Finder's Compress can add __MACOSX, which is refused
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

If it passes, publish a GitHub release with tag `1.2` and attach the ZIP.

## Good to know

- An app in a place the user cannot write is not installed in-app by default; the user is pointed to the release page (`allowsAdministratorInstall`, untested on a real Mac — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- Only HTTPS `GET` requests to GitHub. Headers: `Accept`, `User-Agent`, fixed `Accept-Language: en`. No cookies, no disk cache.

MIT — [LICENSE](LICENSE)
