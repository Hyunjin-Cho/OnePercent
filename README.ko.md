# OnePercent

[English](README.md) · [한국어](README.ko.md)

> **기준일:** 2026-11-22 · 0.1.0 · 관리자 암호가 필요한 설치는 실제 Mac에서 확인할 때까지 기본으로 꺼져 있습니다.

GitHub Releases로 배포하는 macOS 앱의 앱 안 업데이트 부품입니다. 사용자가 [설치]를 눌렀을 때만 내려받고, 내 팀의 Developer ID 서명·Apple 공증·번들 ID·버전과 빌드 번호 상승을 모두 통과해야 앱을 바꿉니다.

## 필요한 것

- macOS 14 이상, Swift 6(Xcode 16 이상)
- **Developer ID**로 서명하고 **공증**받은 앱
- 릴리스마다 버전과 같은 태그(`1.2` — `v1.2` 꼴이면 `tagPrefix: "v"`), `<앱이름>_<태그>.zip` 하나, 올린 `CFBundleVersion`
- 업데이트가 앱을 다시 여는 동안 `applicationShouldTerminate`에서 `.terminateCancel`을 돌려주지 않기

## 추가하기

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.0"))
```

## 쓰기

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp", teamIdentifier: "ABCDE12345",
    bundleIdentifier: "com.example.yourapp", appName: "YourApp"))

updater.noteLaunch()   // 실행할 때 한 번. 업데이트 직후면 새 버전을 돌려줍니다
updater.onUpdateAvailable = { update in /* 직접 만든 알림. 여기서 설치하지 않습니다 */ }
updater.willRelaunch = { /* 저장할 것은 여기서 — 새 앱이 applicationWillTerminate보다 먼저 뜹니다 */ }
updater.startAutomaticChecks()

// 설정 화면: await updater.checkNow() · [설치] 버튼: await updater.installAvailableUpdate()
```

화면은 `updater.presentation`과 `OnePercentText`(29개 언어)로 만듭니다. 다른 설정은 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 문서 주석에 있습니다.

## 릴리스 만들기

```sh
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip   # Finder [압축]은 __MACOSX가 들어가 거부될 수 있습니다
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

통과하면 태그 `1.2`로 GitHub 릴리스를 올리고 ZIP을 붙입니다.

## 알아 둘 것

- 사용자가 쓸 수 없는 위치의 앱은 기본으로 앱 안에서 설치하지 않고 릴리스 페이지로 안내합니다(`allowsAdministratorInstall`, 실제 Mac 확인 전 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- GitHub로 HTTPS `GET`만 보냅니다. 헤더는 `Accept`·`User-Agent`·고정 `Accept-Language: en`이고, 쿠키·디스크 캐시는 쓰지 않습니다.

MIT — [LICENSE](LICENSE)
