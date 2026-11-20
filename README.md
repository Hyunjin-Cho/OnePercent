# OnePercent

> **기준일 (as of):** 2026-11-20 · **Status:** work in progress — no code yet. The first code lands in the next pull request.

A small in-app updater for macOS apps that ship through GitHub Releases. Free, MIT, no third-party code.

**Why the name:** an updater should be the 1% of your app nobody has to think about. It checks quietly, verifies everything, and only swaps the app when the user presses Install.

## Planned

- Check your app's latest GitHub release — on a schedule you choose, or when the user asks.
- Download the release ZIP over HTTPS and inspect it before unpacking.
- Install only when the new app passes every check: same bundle ID, your Developer ID team, Apple notarization, and a higher version.
- Replace the app in place and relaunch it, asking for an administrator password only when the app folder is not writable by the user.
- Your version format: `1.0`, `1.2.3`, `2026.11.17`, or a rule of your own.
- Messages in 29 languages.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Hyunjin Cho.
