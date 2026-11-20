# Manual test on a real Mac

> **기준일:** 2026-11-20 · **Status:** not run yet. Fill in the result column (date, macOS version, pass/fail, notes) each time.

Automated tests cover everything except what needs a real signature, a real password prompt and a real relaunch. Run these with a real app that uses OnePercent, two notarized builds of it (old and new), and a test repository.

## Setup

1. Make two notarized builds: **old** (for example 1.0, build 1) and **new** (1.1, build 2).
2. Zip the new one with `ditto -c -k --keepParent` and check it with `onepercent-check` (README → Making a release).
3. Publish it as the latest release of a **test repository**. In a Debug build of the old app you can point OnePercent there:
   `defaults write <bundle id> <prefix>allowTestRepository -bool true` and `defaults write <bundle id> <prefix>testRepository owner/test-repo`
   (Release builds ignore both.)
4. Back up the app's preferences before each run (`~/Library/Preferences/<bundle id>.plist`).

## Cases

| # | Case | Steps | Expected | Result |
|---|---|---|---|---|
| 1 | Normal update, user-owned | Old app in `/Applications` (owned by you). Check now → Install. | Downloads, verifies, the app reopens as 1.1, "Updated to 1.1." on the first launch. No `.<App>.app.onepercent-*` left in `/Applications`, no `OnePercent-<bundle id>-*` left in `$TMPDIR`. | |
| 2 | Administrator path | `sudo chown -R root:wheel /Applications/<App>.app`, then Install. | A password prompt. After the password the app reopens as 1.1, still owned by root, no ACLs (`ls -le`), no setuid bits. No `/Applications/.<App>.app.old-*` left. | |
| 3 | Administrator path, standard account | Log in as a standard (non-admin) user, app installed by an admin. Install. | A prompt for an administrator name and password; same result as 2. | |
| 4 | Cancel the password prompt | As 2, press Cancel in the prompt. | "The update was cancelled." The old app still opens. | |
| 5 | Cancel a download | Throttle the network (Network Link Conditioner), Install, then Cancel. | "The update was cancelled." Install stays available. | |
| 6 | Force quit while downloading | Install, force quit during the download. Reopen. | Nothing left in `$TMPDIR` after the reopen (removed at launch). | |
| 7 | Force quit while replacing (user path) | Install, force quit right after "Installing…". Reopen. | The app opens (old or new); no `.<App>.app.onepercent-*` left next to it after the reopen. | |
| 8 | Translocated | Download the old app's ZIP with a browser, open it from Downloads without moving it. Install. | "macOS is running the app from a temporary location…" | |
| 9 | Disk image | Run the old app from a mounted DMG. Install. | "…read-only disk…" | |
| 10 | Wrong signer | Upload a ZIP of the app signed with another Team (or ad-hoc). Install. | Refused: "…isn't signed by the expected team, the code signature check failed…". Old app untouched. | |
| 11 | Not notarized | Upload a Developer ID-signed but not notarized build. Install. | Refused: "…the Apple notarization check failed". | |
| 12 | Tag without its ZIP | Publish a newer tag with no asset. Check now. | "The installer for version … isn't ready yet." Not shown as up to date. Attach the ZIP; the next check finds it. | |
| 13 | Languages | Switch the app's language (System Settings → General → Language & Region → Applications). | OnePercent text follows the app's language. | |
