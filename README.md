<a id="korean"></a>

# OnePercent

**한국어** · [English](#english) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md)

> **기준일:** 2026-11-20
> **상태:** 첫 버전(0.1, 아직 릴리스 전). 자동 시험은 모두 통과했습니다. 관리자 암호를 묻는 설치는 실제 Mac에서 확인할 때까지 기본으로 꺼 두었습니다 — [알려진 한계](#알려진-한계) 참고.

<!-- 2026-11-20 오너: 닦아 저장소처럼 README.md 에 한국어(위)·영어(아래), 일본어·간체·번체는 따로 파일로 둔다.
     한 판을 고치면 다섯 판(README.md 의 두 판 + README.ja.md·README.zh-Hans.md·README.zh-Hant.md)을 같이 고친다.
     한국어 설명은 존댓말(~습니다)로 쓴다(닦아 2026-11-18 오너 규칙과 같다). -->

GitHub Releases로 배포하는 macOS 앱을 위한 작은 앱 안 업데이트 부품입니다. 무료이고 MIT이며, 남의 코드는 한 줄도 없습니다.

**이름의 뜻:** 업데이트 부품은 앱에서 아무도 신경 쓰지 않아도 되는 1%여야 합니다. 조용히 확인하고, 모든 것을 검증하고, 사용자가 [설치]를 눌렀을 때만 앱을 바꿉니다.

## 하는 일

1. **확인** — 저장소의 최신 GitHub 릴리스를 정한 주기마다, 또는 사용자가 원할 때 확인합니다. 자동 확인은 알리기만 합니다. 사용자가 [설치]를 누르기 전에는 아무것도 내려받지 않습니다.
2. **내려받기** — HTTPS로 릴리스 ZIP을 받습니다. 그 저장소의 릴리스 주소만 받고, 받는 동안 크기를 제한하며, GitHub가 공개한 SHA-256 값이 있으면 대조합니다.
3. **풀기 전에 ZIP 검사** — ZIP의 목록을 직접 읽어 앱 밖 경로, 심볼릭 링크 아래의 항목, 주석, ZIP64, 지나치게 큰 압축을 거부합니다. 그다음 `ditto`로 풀면서 디스크에 쌓인 양(확장 속성 포함)·항목 수·걸린 시간을 지켜봅니다.
4. **앱 검증** — 아래를 모두 통과해야만 설치합니다.
   - 진짜 앱 폴더이고, 맨 위에 `<앱이름>.app` 하나만 있으며, 앱 밖을 가리키는 링크가 없을 것
   - 번들 ID가 같을 것
   - Apple이 발급한 **Developer ID** 인증서로 **내 팀**이 서명했을 것 — Security.framework(엄격 플래그)와 `codesign --deep --strict`로 두 번, 같은 코드 요구사항 하나로 확인합니다. 같은 팀이라도 개발용 인증서로 서명한 빌드는 거부합니다
   - Apple **공증**을 받았을 것(`spctl`)
   - 버전과 빌드 번호가 **둘 다** 지금 앱보다 높을 것
   - 안내한 바로 그 버전일 것
5. **옛 앱을 먼저 지우지 않고 바꾸기** — 사용자 소유 앱은 바로 옆에 복사해 권한을 정리하고 다시 확인한 뒤 한 번에 바꿉니다. 사용자가 쓸 수 없는 위치의 앱(관리자 암호가 필요한 경우)은 기본으로 앱 안에서 설치하지 않고, 릴리스 페이지에서 직접 바꾸라고 안내합니다(`allowsAdministratorInstall`로 켤 수 있습니다).
6. **다시 열기** — 새 버전을 열고, 다음 실행 때 앱에 "방금 업데이트됐다"고 알려 줍니다.

업데이트가 중간에 끊긴 흔적(강제 종료, 전원 꺼짐)은 다음 실행 때 치웁니다.

## 필요한 것

- macOS 14 이상, Swift 6 도구(Xcode 16 이상)
- **Developer ID**로 서명하고 **공증**받은 GitHub 릴리스
- 릴리스마다 버전 그 자체인 태그(예: `1.2` 또는 `v1.2`)와, `<앱이름>_<태그>.zip` 이름의 ZIP 파일 하나
- 릴리스마다 `CFBundleVersion`(빌드 번호)도 올릴 것 — 점으로 나눈 숫자 1~4마디, 마디당 18자리까지(`202611201530` 같은 날짜·시각형도 됩니다)
- 업데이트가 앱을 다시 열 때 앱이 종료를 거부하지 않을 것(`applicationShouldTerminate`에서 `.terminateCancel`을 돌려주지 않기)

## 추가하기

Swift Package Manager:

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", branch: "main")
```

그리고 앱 타깃의 의존성에 `"OnePercent"`를 넣습니다.

## 쓰기

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp",          // GitHub 의 owner/name
    teamIdentifier: "ABCDE12345",       // Developer ID 팀
    bundleIdentifier: "com.example.yourapp",
    appName: "YourApp"))                // ZIP 안에 YourApp.app

// 실행할 때:
if let version = updater.noteLaunch() {
    // `version` 으로 업데이트한 뒤 첫 실행 — 원하면 알려 줍니다:
    // OnePercentText.updated(to: version)
}
updater.onUpdateAvailable = { update in
    // 직접 만든 알림을 보여 줍니다. 여기서 설치하지 않습니다.
}
updater.installGuard = {
    timer.isRunning ? "타이머를 먼저 멈춰 주세요." : nil   // 막을 이유, 없으면 nil
}
updater.willRelaunch = {
    // 새 앱이 이 앱의 applicationWillTerminate 보다 먼저 뜹니다 — 저장할 것은 여기서 저장합니다.
}
updater.startAutomaticChecks()

// 설정 화면에서:
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()   // 다시 켠 뒤라면 먼저 GitHub 에 다시 묻고 설치합니다
updater.cancel()                         // 내려받거나 확인하는 중에
```

`OnePercentUpdater`는 `@Observable`입니다. 화면은 `updater.presentation`(어떤 줄을 보일지, [설치]·[취소] 버튼을 보일지, 마지막 오류)을 읽어 만들고, 문구는 `OnePercentText`에 준비된 것을 쓰면 됩니다. 미리보기용으로 `UpdateStatusPresentation`과 `AvailableUpdate`를 직접 만들 수도 있습니다.

## 릴리스 만들기

```sh
# 1. 평소처럼 YourApp.app 을 빌드하고, Developer ID 로 서명하고, 공증받고, 스테이플합니다.
#    CFBundleShortVersionString 과 CFBundleVersion 을 둘 다 올립니다.
# 2. 부모 폴더를 유지한 채 압축합니다:
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. 사용자 Mac 에서 돌 코드와 같은 코드로 미리 검사합니다(이전 릴리스와 비교):
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
# 4. 태그 1.2 로 GitHub 릴리스를 올리고 YourApp_1.2.zip 을 붙입니다.
```

Finder의 [압축]으로 ZIP을 만들지 마세요 — `__MACOSX` 폴더가 들어갈 수 있고, 그런 ZIP은 거부됩니다. 앱 이름에 공백이 있으면 공백 없는 `assetName`을 정하세요 — GitHub가 올린 파일 이름을 바꿀 수 있습니다. `onepercent-check --help`로 모든 옵션을 볼 수 있습니다.

## 설정

앞의 네 가지만 꼭 필요합니다.

| 설정 | 기본값 | 뜻 |
|---|---|---|
| `repository` | — | GitHub `owner/name`. 초안·사전 배포가 아닌 최신 릴리스만 봅니다. |
| `teamIdentifier` | — | 10자리 팀 ID. 다른 사람이 서명한 파일은 거부합니다. |
| `bundleIdentifier` | — | 내려받은 앱이 가져야 할 번들 ID. |
| `appName` | — | `.app`을 뺀 앱 이름. |
| `versionScheme` | `.numeric` | 버전을 읽고 비교하는 규칙(아래). |
| `tagPrefix` | `""` | 태그에서 버전 앞에 붙는 글자(예: `"v"`). |
| `assetName` | `<appName>_<tag>.zip` | 태그별 자산 파일 이름. |
| `versionSuffixInfoKey` | 없음 | `CFBundleShortVersionString` 뒤에 붙일 Info.plist 키(예: `_hotfix1`). |
| `requireBuildIncrease` | `true` | `CFBundleVersion`도 올라가야 설치합니다. |
| `schedule` | `.monthly` | `.monthly`, `.weekly`, `.daily`, `.every(초)`(최소 1시간), `.manual`. |
| `automaticChecksByDefault` | `true` | 사용자가 스위치를 만지기 전의 자동 확인 상태. |
| `installLocation` | `.inPlace` | `.inPlace`는 실행 중인 앱이 어디 있든 그 자리에서 바꾸고, `.applicationsFolder`는 `/Applications/<appName>.app`일 때만 설치합니다. |
| `allowsAdministratorInstall` | `false` | 관리자 암호가 필요한 위치의 앱도 앱 안에서 설치합니다(실제 Mac에서 확인한 뒤 켜세요). |
| `defaultsKeyPrefix` | `"OnePercent."` | 저장하는 키의 앞부분. |
| `userAgent` | `<appName>/<버전>` | `User-Agent` 헤더. |
| `limits` | 내려받기 500 MiB, 풀기 항목 5만 개·2 GiB·300초 | 작은 앱은 더 좁혀도 됩니다. |
| `allowedHosts` | GitHub의 API·웹·자산 호스트 | 요청과 리다이렉트가 갈 수 있는 호스트(HTTPS만). |
| `testRepository` | 없음 | 시험할 때 대신 쓸 저장소. 앱의 `#if DEBUG` 안에서만 정하세요. 패키지도 디버그 빌드일 때만 씁니다. |

### 버전 규칙

- `.numeric` — `1`, `1.0`, `1.2.3`, `2026.11.17`. 없는 자리는 0으로 봅니다(`1.0` = `1.0.0`). 자리마다 숫자로 비교합니다(`1.10` > `1.9`).
- `.calendar()` — `YYYY.MM.DD`, 번호 붙은 핫픽스 접미어도 됩니다: `2026.11.17_hotfix2`.
- 직접 만든 규칙: `VersionScheme(name: "build") { text in /* [Int] 또는 nil 을 돌려줍니다 */ }`.

규칙이 읽지 못하는 버전은 절대 더 새것으로 보지 않습니다. 실행 중인 앱의 버전을 규칙이 못 읽으면 `noteLaunch()`가 설정 오류로 알려 줍니다.

## 언어

모든 문구가 29개 언어로 들어 있고, 앱의 언어를 따라갑니다: 체코어, 덴마크어, 독일어, 그리스어, 영어, 스페인어, 핀란드어, 필리핀어, 프랑스어, 헝가리어, 인도네시아어, 이탈리아어, 일본어, 한국어, 말레이어, 노르웨이어, 네덜란드어, 폴란드어, 포르투갈어(브라질·포르투갈), 루마니아어, 러시아어, 스웨덴어, 태국어, 튀르키예어, 우크라이나어, 베트남어, 중국어(간체·번체). 한국어가 원문이고, 나머지는 원문을 바탕으로 썼습니다.

## 밖으로 보내는 것

GitHub로 가는 HTTPS `GET` 요청뿐입니다(릴리스 정보는 `api.github.com`, ZIP은 `github.com`과 그 자산 호스트). OnePercent가 넣는 헤더는 `Accept`, `User-Agent`, `Accept-Language: en` 세 개입니다. 언어 헤더는 고정값이라 사용자의 언어 목록이 나가지 않습니다. 쿠키·디스크 캐시·식별자·사용자 데이터는 보내지 않습니다. GitHub는 이 요청을 다른 웹 요청과 똑같이 봅니다(IP 주소 포함).

## 저장하는 값

`UserDefaults`(또는 직접 넘긴 저장소)에 다음을 저장합니다: 자동 확인을 켰는지, 마지막으로 성공한 확인, 설치할 수 있었던 최신 버전, 마지막으로 알린 버전, 마지막으로 실행한 버전. `OnePercentUpdater.storedKeys(configuration:)`가 모든 키를 알려 주므로, 앱이 스스로를 초기화할 때 지울 수 있습니다.

## 알려진 한계

- **관리자 경로는 기본으로 꺼져 있습니다.** 보안 리뷰에서 찾은 문제는 고쳤고 대역 명령으로 시험했지만, 실제 암호 창으로는 아직 해 보지 않았습니다. 확인 목록은 [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)(영어)입니다.
- 관리자 경로를 켜면, 관리자 복사가 도는 동안 앱의 메인 스레드가 기다립니다(시스템 암호 창이 `NSAppleScript`를 거치고, 이것은 메인 스레드에 있어야 합니다).
- 새 앱이 옛 앱보다 먼저 열리므로, 잠깐 둘이 같이 떠 있을 수 있습니다.
- 델타 업데이트, 단계적 배포, 별도 EdDSA 서명은 없습니다. 진위는 Developer ID, 공증, 안내한 버전 대조에 기댑니다.

## 개발

```sh
swift test
```

시험은 네트워크, `/Applications`, 사용자 설정을 건드리지 않습니다. 임시 폴더에 가짜 앱을 만들고 실제 `ditto`, 실제 풀기 감시, 실제 관리자 셸 스크립트(대역 명령으로)를 돌립니다.

## 감사의 말

OnePercent는 하늘키보드 안의 업데이트 부품에서 시작해, 같은 작성자가 여기로 일반화했습니다. 전체 흐름은 처음에 [exelban/stats](https://github.com/exelban/stats)(MIT)를 참고했습니다. [Sparkle](https://github.com/sparkle-project/Sparkle)(MIT), [mxcl/AppUpdater](https://github.com/mxcl/AppUpdater)(Unlicense), [Squirrel.Mac](https://github.com/Squirrel/Squirrel.Mac)(MIT)에서도 코드가 아니라 아이디어를 얻었습니다.

## 라이선스

MIT — [LICENSE](LICENSE) 참고. Copyright (c) 2026 Hyunjin Cho.

---

<a id="english"></a>

# OnePercent — English

[한국어](#korean) · **English** · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md)

> **As of:** 2026-11-20
> **Status:** first version (0.1, unreleased). Automated tests pass. Installs that need an administrator password are off by default until they have been tried on a real Mac — see [Known gaps](#known-gaps).

A small in-app updater for macOS apps that ship through GitHub Releases. Free, MIT, no third-party code.

**Why the name:** an updater should be the 1% of your app nobody has to think about. It checks quietly, verifies everything, and only swaps the app when the user presses Install.

## What it does

1. **Checks** your repository's latest GitHub release — on a schedule you choose, or when the user asks. Background checks only *tell* the user; nothing is downloaded until they press Install.
2. **Downloads** the release ZIP over HTTPS (only release addresses of your repository, size-limited while receiving, SHA-256 compared with GitHub's published digest when there is one).
3. **Inspects the ZIP before unpacking** — it reads the ZIP's own listing and refuses paths outside the app, entries under symbolic links, comments, ZIP64 and oversized archives — then unpacks with `ditto` while watching bytes (extended attributes included), item count and time on disk.
4. **Verifies the app**, and installs only if every check passes:
   - a real app folder, exactly `<YourApp>.app` at the top level, no links pointing outside it;
   - your bundle ID;
   - an Apple-issued **Developer ID** certificate of **your Team**, checked twice (Security.framework with strict flags, and `codesign --deep --strict`), with one code requirement — a build signed with a development certificate of the same Team is refused;
   - Apple **notarization** (`spctl`);
   - a higher version **and** a higher build number than the running app;
   - exactly the version that was announced.
5. **Replaces the app without deleting it first.** A user-owned app is copied next to itself, its permissions cleaned, re-checked, and swapped in one step. An app the user cannot write (it would need an administrator password) is not installed in-app by default; the user is told to replace it from the release page (turn on `allowsAdministratorInstall` to allow it).
6. **Reopens** the new version, and tells your app on the next launch that it was just updated.

Leftovers of an interrupted update (force quit, power loss) are removed at the next launch.

## Requirements

- macOS 14 or later, Swift 6 toolchain (Xcode 16 or later).
- Releases on GitHub, signed with **Developer ID** and **notarized**.
- Each release: a tag that is your version (for example `1.2` or `v1.2`), and one ZIP asset named `<YourApp>_<tag>.zip`.
- Raise `CFBundleVersion` (the build number) with every release — one to four dot-separated numbers of up to 18 digits each (date-time builds such as `202611201530` work).
- Your app must not refuse to quit while an update reopens it (do not return `.terminateCancel` from `applicationShouldTerminate`).

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
updater.willRelaunch = {
    // The new copy starts before this one's applicationWillTerminate — save what you need here.
}
updater.startAutomaticChecks()

// In your settings:
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()   // after a relaunch it asks GitHub again first, then installs
updater.cancel()                         // while downloading or verifying
```

`OnePercentUpdater` is `@Observable`. For your UI, read `updater.presentation` — which line to show, whether to show the Install or Cancel button, and the last error — and use `OnePercentText` for ready-made strings. For previews you can build `UpdateStatusPresentation` and `AvailableUpdate` values yourself.

## Making a release

```sh
# 1. Build, sign with Developer ID, notarize and staple YourApp.app as usual.
#    Raise both CFBundleShortVersionString and CFBundleVersion.
# 2. Zip it with the parent folder kept:
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. Check it with the same code your users' Macs will run (against the previous release):
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
# 4. Publish a GitHub release with tag 1.2 and attach YourApp_1.2.zip.
```

Do not make the ZIP with Finder's Compress — it can add a `__MACOSX` folder, which is refused. If your app name has spaces, choose an `assetName` without them — GitHub may rename uploaded files. `onepercent-check --help` lists every option.

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
| `allowsAdministratorInstall` | `false` | Also install in-app where an administrator password is needed (turn on after trying it on a real Mac). |
| `defaultsKeyPrefix` | `"OnePercent."` | Prefix of the stored keys. |
| `userAgent` | `<appName>/<version>` | The `User-Agent` header. |
| `limits` | 500 MiB download; 50,000 items, 2 GiB, 300 s unpacking | Small apps may tighten these. |
| `allowedHosts` | GitHub's API, web and asset hosts | Hosts that requests and redirects may reach (HTTPS only). |
| `testRepository` | none | A repository to use instead while testing. Set it only inside your app's `#if DEBUG`; the package also uses it only in its own debug builds. |

### Version schemes

- `.numeric` — `1`, `1.0`, `1.2.3`, `2026.11.17`. Missing parts count as zero (`1.0` = `1.0.0`). Parts compare as numbers (`1.10` > `1.9`).
- `.calendar()` — `YYYY.MM.DD` with an optional numbered hotfix suffix: `2026.11.17_hotfix2`.
- Your own: `VersionScheme(name: "build") { text in /* return [Int] or nil */ }`.

A version the scheme cannot read is never treated as newer. If it cannot read the running app's version, `noteLaunch()` reports a configuration error.

## Languages

All messages come in 29 languages and follow your app's language: Czech, Danish, German, Greek, English, Spanish, Finnish, Filipino, French, Hungarian, Indonesian, Italian, Japanese, Korean, Malay, Norwegian, Dutch, Polish, Portuguese (Brazil and Portugal), Romanian, Russian, Swedish, Thai, Turkish, Ukrainian, Vietnamese and Chinese (Simplified and Traditional). The Korean text is the original; the others were written from it.

## What it sends

Only HTTPS `GET` requests to GitHub (`api.github.com` for the release, `github.com` and its asset hosts for the ZIP). OnePercent sets three headers: `Accept`, `User-Agent` and `Accept-Language: en` — fixed, so your user's language list is not sent. No cookies, no disk cache, no identifiers, nothing about the user's data. GitHub sees the request as it sees any web request (including the IP address).

## Stored values

In `UserDefaults` (or a store you pass): whether background checks are on, the last successful check, the latest installable version seen, the last announced version and the last launched version. `OnePercentUpdater.storedKeys(configuration:)` lists every key, so your app can remove them when it resets itself.

## Known gaps

- **The administrator path is off by default.** The problems found in the security review are fixed and tested with stand-in commands, but it has not been tried with a real password prompt yet. [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md) is the checklist.
- With the administrator path on, the app's main thread waits while the administrator copy runs (the system password prompt goes through `NSAppleScript`, which must stay on the main thread).
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
