# Manual test on a real Mac

> **기준일:** 2026-11-22 · **Status:** partly run — see the result column. Fill it in (date, macOS version, pass/fail, notes) each time.
> 2026-11-22: 1, 5, 6, 7, 8, 9, 10, 11, 12, 13 pass. **2, 3, 4, 4b** need a person: `sudo`, the administrator password prompt, a standard account.
> Notarizing: any notarytool profile of the same Team works (profiles are per Apple account, not per app) — `make-app.sh … --notarize <profile>`.
> Check a profile with `xcrun notarytool history --keychain-profile <profile>`; `security find-generic-password` does not see notarytool profiles and reports none.
> 2026-11-20: the administrator path is **off by default** (`allowsAdministratorInstall = false`) until cases 2–4 pass. Turn it on in a test build for those cases.
> 2026-11-22 (#8): the test repository must be **public** — OnePercent asks GitHub without signing in, and a private repository answers 404 ("No release was found").

Automated tests cover everything except what needs a real signature, a real password prompt and a real relaunch. Run these with a real app that uses OnePercent, builds of it signed with Developer ID (the new one notarized), and a public test repository.

## Setup

2026-11-22: `TestApp/` builds a ready-made test app, **OnePercentTestApp** (owner decision: a dedicated test app, so most cases run without anyone at the keyboard). Your own app works too (step 5).

1. Build: `TestApp/make-app.sh VERSION BUILD owner/test-repo [--adhoc] [--notarize PROFILE] [--padding MB]`
   → `TestApp/dist/VERSION/OnePercentTestApp.app` and `OnePercentTestApp_VERSION.zip`. Developer ID signed with the hardened runtime and a secure timestamp (the Team ID is read from the keychain's "Developer ID Application" identity). `--adhoc` signs ad-hoc (case 10), `--notarize` submits to Apple and staples, `--padding` adds random bytes so a download takes a while (cases 5, 6).
2. The **old** build stays local (for example 1.0, build 1). Each **new** build is the latest release of a **public test repository** — tag = version, the ZIP attached.
3. Drive it with the buttons, or with launch arguments: `open -n TestApp/dist/1.0/OnePercentTestApp.app --args --auto-install` (also `--check-only`, `--cancel-at 0.3`, `--allow-admin`; `-AppleLanguages "(ja)"` for case 13). Every step goes to `~/Library/Logs/OnePercentTestApp.log`.
4. Reset the app's stored values between runs: `defaults delete com.example.OnePercentTestApp`.
5. With your own app instead: Developer ID builds, the new one notarized, zipped with `ditto -c -k --keepParent` and checked with `onepercent-check` (README → Making a release). In a Debug build of the old app, point OnePercent at the test repository in code:
   `#if DEBUG` · `configuration.testRepository = "owner/test-repo"` · `#endif` (Release builds of the package ignore it).

Two things GitHub does (measured 2026-11-22):
- It caches answers to unauthenticated API requests for up to **60 seconds** (`cache-control: public, max-age=60, s-maxage=60`). Right after publishing a release or attaching a ZIP, a check can still see the old answer — wait a minute.
- Unauthenticated requests are limited to **60 an hour** per IP address, and every check is one.

## Cases

| # | Case | Steps | Expected | Result |
|---|---|---|---|---|
| 1 | Normal update, user-owned | Old app in `/Applications` (owned by you). Check now → Install. | Downloads, verifies, the app reopens as 1.1, "Updated to 1.1." on the first launch. No `.<App>.app.onepercent-*` left in `/Applications`, no `OnePercent-<bundle id>-*` left in `$TMPDIR`. | 2026-11-22 · macOS 27.2.1 · **pass** — notarized TestApp 1.0 in `/Applications` (owned by the user), `--auto-install` → 1.5 (notarized): download, verify, install, "relaunching"; the new process logged `v1.5(6)` from the same path with "1.5로 업데이트했어요."; one process running; still owned by the user; `codesign --verify --deep --strict` valid, `spctl` "Notarized Developer ID"; no staging copy, no work folder. |
| 2 | Administrator path | With `allowsAdministratorInstall = true`: `sudo chown -R root:wheel /Applications/<App>.app`, then Install. | A password prompt. After the password the app reopens as 1.1, still owned by root, no ACLs (`ls -le`), no setuid bits. No `/Applications/.<App>.app.old-*` left. | |
| 3 | Administrator path, standard account | Log in as a standard (non-admin) user, app installed by an admin. Install. | A prompt for an administrator name and password; same result as 2. | |
| 4 | Cancel the password prompt | As 2, press Cancel in the prompt. | "The update was cancelled." The old app still opens. | |
| 4b | Administrator path off (default) | As 2 but with `allowsAdministratorInstall = false`. | "…can only be replaced with an administrator password…" before anything is downloaded. | |
| 5 | Cancel a download | Throttle the network (Network Link Conditioner), Install, then Cancel. Or: a large release (`--padding 150`) and `--cancel-at 0.3`. | "The update was cancelled." Install stays available. | 2026-11-22 · macOS 27.2.1 · **pass** — 1.0 → 1.4 (150 MB), Cancel at 30 %: "업데이트를 취소했어요.", phase back to available 1.4 (Install stays); no work folder left. |
| 6 | Force quit while downloading | Install, force quit during the download. Reopen **after 10 minutes** (younger leftovers are kept in case another copy is updating). | Nothing left in `$TMPDIR` after the reopen (removed at launch). | 2026-11-22 · macOS 27.2.1 · **pass** — `kill -9` at 20 % of 1.4: one work folder left (41 MB partial ZIP). Reopened at once: kept (younger than 10 minutes). Folder time set 15 minutes back with `touch` (simulated wait), reopened: removed. |
| 7 | Force quit while replacing (user path) | Install, force quit right after "Installing…". Reopen after 10 minutes. | The app opens (old or new); no `.<App>.app.onepercent-*` left next to it after the reopen. | 2026-11-22 · macOS 27.2.1 · **pass** — notarized 1.0 in `/Applications` → 1.6 (notarized, 150 MB), `kill -9` the moment "installing" appeared: the installed app was still **1.0 with a valid signature**; one staging copy next to it and one work folder left. Reopened at once: 1.0 opened, both kept (younger than 10 minutes). Their time set 15 minutes back with `touch` (simulated wait), reopened: both removed. ⚠️ Timing: on APFS the copy is a clone (instant) and the re-check of a small app takes well under 0.1 s — with a small app, or any delay before the kill, the swap and the reopen finish first (two tries missed this way). Use a large release and kill without waiting. |
| 8 | Translocated | Download the old app's ZIP with a browser, open it from Downloads without moving it. Install. | "macOS is running the app from a temporary location…" | 2026-11-22 · macOS 27.2.1 · **pass** (download simulated) — notarized 1.0 unzipped into a folder and given the quarantine attribute a browser sets, with the "user approved" flag (`00c1;…;Safari;…`) so no Gatekeeper prompt appeared; launched without moving it: it ran from `…/AppTranslocation/…`, and Install answered "macOS가 앱을 임시 위치에서 실행하고 있어요…" before any download. |
| 9 | Disk image | Run the old app from a mounted DMG. Install. | "…read-only disk…" | 2026-11-22 · macOS 27.2.1 · **pass** — TestApp 1.0 from a read-only DMG, latest 1.3: "…읽기 전용 디스크(디스크 이미지 등)에서 실행 중이에요…" with no download started. |
| 10 | Wrong signer | Upload a ZIP of the app signed with another Team (or ad-hoc). Install. | Refused: "…isn't signed by the expected team, the code signature check failed…". Old app untouched. | 2026-11-22 · macOS 27.2.1 · **pass** — 1.0 → 1.2 ad-hoc: refused after download with "서명한 팀이 다름, 코드 서명 확인 실패, Apple 공증 확인 실패"; old app still 1.0; no staging copy, no work folder left. |
| 11 | Not notarized | Upload a Developer ID-signed but not notarized build. Install. | Refused: "…the Apple notarization check failed". | 2026-11-22 · macOS 27.2.1 · **pass** — 1.0 → 1.3 (Developer ID, not notarized): refused with "Apple 공증 확인 실패" only; old app still 1.0; nothing left. |
| 12 | Tag without its ZIP | Publish a newer tag with no asset. Check now. | "The installer for version … isn't ready yet." Not shown as up to date. Attach the ZIP; the next check finds it. | 2026-11-22 · macOS 27.2.1 · **pass** — tag 1.1 without a ZIP: "새 버전 1.1의 설치 파일이 아직 준비되지 않았어요", latest not stored. After attaching the ZIP the next check still saw the old answer (GitHub's 60-second cache, see Setup); a minute later: available 1.1. |
| 13 | Languages | Switch the app's language (System Settings → General → Language & Region → Applications). | OnePercent text follows the app's language. | 2026-11-22 · macOS 27.2.1 · **pass** — launched with `-AppleLanguages`: ja "今すぐ確認", de "Jetzt prüfen", zh-Hant "立即檢查"; system language ko "지금 확인". |
