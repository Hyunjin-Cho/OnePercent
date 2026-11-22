# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · **繁體中文**

> **基準日：** 2026-11-22 · 0.1.0 · 需要管理者密碼的安裝在實機驗證之前預設關閉。

<!-- README.md（韓文·英文）的繁體中文版。修改 README.md 時也要同時修改此檔案。 -->

為透過 GitHub Releases 發佈的 macOS App 準備的小型 App 內更新元件。只有使用者按下［安裝］時才會下載，並且只有通過你團隊的 Developer ID 簽章、Apple 公證、Bundle ID、版本號與建置號提升的全部檢查，才會取代 App。

## 需要什麼

- macOS 14 或更新版本，Swift 6（Xcode 16 或更新版本）
- 使用 **Developer ID** 簽章並通過**公證**的 App
- 每個發佈：與版本相同的標籤（`1.2` — 若為 `v1.2`，設定 `tagPrefix: "v"`）、一個 `<App 名稱>_<標籤>.zip`、提高後的 `CFBundleVersion`
- 更新重新開啟 App 期間，`applicationShouldTerminate` 不要回傳 `.terminateCancel`

## 加入

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.0"))
```

## 使用

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp", teamIdentifier: "ABCDE12345",
    bundleIdentifier: "com.example.yourapp", appName: "YourApp"))

updater.noteLaunch()   // 啟動時呼叫一次。剛更新完時回傳新版本
updater.onUpdateAvailable = { update in /* 顯示你自己的通知。不要在這裡安裝 */ }
updater.willRelaunch = { /* 需要儲存的內容在這裡儲存 — 新 App 會先於 applicationWillTerminate 啟動 */ }
updater.startAutomaticChecks()

// 設定畫面: await updater.checkNow() · ［安裝］按鈕: await updater.installAvailableUpdate()
```

畫面由 `updater.presentation` 和 `OnePercentText`（29 種語言）建構。其他設定見 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 的文件註解。

## 製作發佈

```sh
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip   # Finder 的［壓縮］可能加入 __MACOSX 而被拒絕
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通過後，用標籤 `1.2` 發佈 GitHub Release 並附上 ZIP。

## 注意事項

- 使用者無法寫入位置的 App，預設不在 App 內安裝，而是引導使用者到發佈頁面（`allowsAdministratorInstall`，尚未在實機驗證 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 傳送 HTTPS `GET` 請求。標頭為 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 與磁碟快取。

MIT — [LICENSE](LICENSE)
