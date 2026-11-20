# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · **繁體中文**

> **基準日：** 2026-11-20
> **狀態：** 第一個版本（0.1，尚未發佈）。自動測試全部通過。需要管理者密碼的安裝在實機確認之前預設關閉 — 請參閱[已知限制](#已知限制)。

<!-- 2026-11-20: README.md（韓文·英文）的繁體中文版。修改 README.md 時也要同時修改此檔案。 -->

一個為透過 GitHub Releases 發佈的 macOS App 準備的小型 App 內更新元件。免費、MIT，不含任何一行第三方程式碼。

**名字的由來：** 更新元件應該是 App 裡那 1% 誰都不用操心的部分。它安靜地檢查、驗證一切，只有在使用者按下［安裝］時才替換 App。

## 它做什麼

1. **檢查** — 依照你設定的間隔，或在使用者想要時，檢查儲存庫最新的 GitHub 發佈。自動檢查只負責通知；在使用者按下［安裝］之前不會下載任何東西。
2. **下載** — 透過 HTTPS 取得發佈的 ZIP。只接受該儲存庫的發佈位址，接收時限制大小，若 GitHub 公佈了 SHA-256 就進行比對。
3. **解壓縮前檢查 ZIP** — 直接讀取 ZIP 的目錄，拒絕 App 之外的路徑、符號連結下的項目、註解、ZIP64 和過大的壓縮檔；接著用 `ditto` 解壓縮，同時監看寫入磁碟的資料量（含延伸屬性）、項目數和耗時。
4. **驗證 App** — 以下全部通過才會安裝：
   - 是真正的 App 檔案夾，最上層只有 `<App 名稱>.app`，沒有指向 App 之外的連結
   - Bundle ID 相同
   - 由 Apple 簽發的 **Developer ID** 憑證、**你的團隊** 簽署 — 用 Security.framework（嚴格旗標）和 `codesign --deep --strict` 檢查兩次，使用同一條程式碼要求。即使是同一團隊，用開發憑證簽署的建置也會被拒絕
   - 已通過 Apple **公證**（`spctl`）
   - 版本和建置編號 **都** 高於目前的 App
   - 正是通知過的那個版本
5. **不先刪除舊 App 就完成替換** — 使用者擁有的 App 會先拷貝到它旁邊、整理權限、再次檢查，然後一次替換。使用者無法寫入的位置的 App（需要管理者密碼時）預設不在 App 內安裝，而是提示使用者從發佈頁面手動替換（可用 `allowsAdministratorInstall` 開啟）。
6. **重新開啟** — 開啟新版本，並在下次啟動時告訴 App「剛剛更新過」。

更新中途中斷留下的痕跡（強制結束、斷電）會在下次啟動時清理。

## 需要什麼

- macOS 14 或以上版本，Swift 6 工具鏈（Xcode 16 或以上版本）
- 用 **Developer ID** 簽署並通過 **公證** 的 GitHub 發佈
- 每個發佈：一個就是版本本身的標籤（例如 `1.2` 或 `v1.2`），以及一個名為 `<App 名稱>_<標籤>.zip` 的 ZIP 檔案
- 每個發佈也要提高 `CFBundleVersion`（建置編號）— 用點分隔的 1～4 段數字，每段最多 18 位（`202611201530` 這類日期時間格式也可以）
- 更新重新開啟 App 時，App 不能拒絕結束（不要在 `applicationShouldTerminate` 中回傳 `.terminateCancel`）

## 加入

Swift Package Manager：

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", branch: "main")
```

接著把 `"OnePercent"` 加入 App 目標的相依項目。

## 使用

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp",          // GitHub 上的 owner/name
    teamIdentifier: "ABCDE12345",       // Developer ID 團隊
    bundleIdentifier: "com.example.yourapp",
    appName: "YourApp"))                // ZIP 裡是 YourApp.app

// 啟動時：
if let version = updater.noteLaunch() {
    // 更新到 `version` 後的第一次啟動 — 需要的話可以告訴使用者：
    // OnePercentText.updated(to: version)
}
updater.onUpdateAvailable = { update in
    // 顯示你自己的通知。不要在這裡安裝。
}
updater.installGuard = {
    timer.isRunning ? "請先停止計時器。" : nil   // 阻止的理由，沒有就回傳 nil
}
updater.willRelaunch = {
    // 新的 App 會在本 App 的 applicationWillTerminate 之前啟動 — 需要儲存的內容在這裡儲存。
}
updater.startAutomaticChecks()

// 在設定畫面中：
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()   // 如果是重新啟動之後，會先再問一次 GitHub 再安裝
updater.cancel()                         // 下載或檢查過程中
```

`OnePercentUpdater` 是 `@Observable` 的。畫面讀取 `updater.presentation`（顯示哪一行、是否顯示［安裝］·［取消］按鈕、最近的錯誤）來建構，文字可以使用 `OnePercentText` 中準備好的內容。預覽時也可以自行建立 `UpdateStatusPresentation` 和 `AvailableUpdate`。

## 製作發佈

```sh
# 1. 照常建置 YourApp.app，用 Developer ID 簽署，進行公證並裝訂（staple）。
#    同時提高 CFBundleShortVersionString 和 CFBundleVersion。
# 2. 保留父檔案夾進行壓縮：
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. 用與使用者 Mac 上執行的相同程式碼預先檢查（與上一個發佈比較）：
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
# 4. 用標籤 1.2 建立 GitHub 發佈，並附上 YourApp_1.2.zip。
```

不要用 Finder 的［壓縮］來製作 ZIP — 它可能會加入 `__MACOSX` 檔案夾，這樣的 ZIP 會被拒絕。如果 App 名稱裡有空格，請設定一個不含空格的 `assetName` — GitHub 可能會更改上傳檔案的名稱。用 `onepercent-check --help` 可以查看所有選項。

## 設定

只有前四項是必需的。

| 設定 | 預設值 | 意義 |
|---|---|---|
| `repository` | — | GitHub 的 `owner/name`。只看不是草稿、不是預先發佈的最新發佈。 |
| `teamIdentifier` | — | 10 位團隊 ID。其他人簽署的檔案會被拒絕。 |
| `bundleIdentifier` | — | 下載的 App 必須具有的 Bundle ID。 |
| `appName` | — | 去掉 `.app` 的 App 名稱。 |
| `versionScheme` | `.numeric` | 讀取和比較版本的規則（見下文）。 |
| `tagPrefix` | `""` | 標籤中版本前面的文字（例如 `"v"`）。 |
| `assetName` | `<appName>_<tag>.zip` | 每個標籤的資源檔名。 |
| `versionSuffixInfoKey` | 無 | 附加在 `CFBundleShortVersionString` 後面的 Info.plist 鍵（例如 `_hotfix1`）。 |
| `requireBuildIncrease` | `true` | `CFBundleVersion` 也提高了才安裝。 |
| `schedule` | `.monthly` | `.monthly`、`.weekly`、`.daily`、`.every(秒)`（至少 1 小時）、`.manual`。 |
| `automaticChecksByDefault` | `true` | 使用者碰開關之前的自動檢查狀態。 |
| `installLocation` | `.inPlace` | `.inPlace` 無論執行中的 App 在哪裡都原地替換；`.applicationsFolder` 只在 `/Applications/<appName>.app` 時安裝。 |
| `allowsAdministratorInstall` | `false` | 需要管理者密碼的位置的 App 也在 App 內安裝（請在實機確認後再開啟）。 |
| `defaultsKeyPrefix` | `"OnePercent."` | 儲存的鍵的前綴。 |
| `userAgent` | `<appName>/<版本>` | `User-Agent` 標頭。 |
| `limits` | 下載 500 MiB；解壓縮 5 萬個項目、2 GiB、300 秒 | 小型 App 可以收得更緊。 |
| `allowedHosts` | GitHub 的 API、網頁和資源主機 | 請求和重新導向可以到達的主機（僅限 HTTPS）。 |
| `testRepository` | 無 | 測試時代替使用的儲存庫。只在 App 的 `#if DEBUG` 中設定；元件本身也只在除錯建置中使用它。 |

### 版本規則

- `.numeric` — `1`、`1.0`、`1.2.3`、`2026.11.17`。缺少的段視為 0（`1.0` = `1.0.0`）。每段依數字比較（`1.10` > `1.9`）。
- `.calendar()` — `YYYY.MM.DD`，也可以帶編號的熱修正後綴：`2026.11.17_hotfix2`。
- 自訂規則：`VersionScheme(name: "build") { text in /* 回傳 [Int] 或 nil */ }`。

規則無法讀取的版本絕不會被視為更新的版本。如果規則讀不出執行中 App 的版本，`noteLaunch()` 會回報設定錯誤。

## 語言

所有文字都有 29 種語言，並跟隨 App 的語言：捷克文、丹麥文、德文、希臘文、英文、西班牙文、芬蘭文、菲律賓文、法文、匈牙利文、印尼文、義大利文、日文、韓文、馬來文、挪威文、荷蘭文、波蘭文、葡萄牙文（巴西·葡萄牙）、羅馬尼亞文、俄文、瑞典文、泰文、土耳其文、烏克蘭文、越南文、中文（簡體·繁體）。韓文是原文，其餘依據原文撰寫。

## 對外傳送的內容

只有傳往 GitHub 的 HTTPS `GET` 請求（發佈資訊傳往 `api.github.com`，ZIP 傳往 `github.com` 及其資源主機）。OnePercent 加入的標頭只有 `Accept`、`User-Agent`、`Accept-Language: en` 三個。語言標頭是固定值，所以不會傳送使用者的語言清單。不傳送 Cookie、磁碟快取、識別碼或使用者資料。GitHub 會像對待其他網頁請求一樣看待這些請求（包括 IP 位址）。

## 儲存的值

在 `UserDefaults`（或你傳入的儲存）中儲存：是否開啟自動檢查、最後一次成功的檢查、可安裝的最新版本、最後通知過的版本、最後啟動的版本。`OnePercentUpdater.storedKeys(configuration:)` 會列出所有鍵，App 重設自身時可以刪除它們。如果 App 有刪除自身的功能，也請呼叫 `OnePercentUpdater.removeLeftovers(configuration:olderThan: 0)`，一併清理更新留下的痕跡。

## 已知限制

- **管理者路徑預設關閉。** 安全審查中發現的問題已修正，並用替代指令測試過，但還沒有用真正的密碼視窗試過。確認清單是 [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)（英文）。
- 開啟管理者路徑後，在以管理者身分拷貝期間，App 的主執行緒會等待（系統密碼視窗經過 `NSAppleScript`，而它必須在主執行緒上執行）。
- 新的 App 會在舊 App 結束前開啟，所以可能會有片刻兩者同時執行。
- 沒有增量更新、分階段推送或另外的 EdDSA 簽章。真實性依靠 Developer ID、公證和與通知版本的比對。

## 開發

```sh
swift test
```

測試不會接觸網路、`/Applications` 或使用者設定。它們在暫存檔案夾中建立假的 App，執行真正的 `ditto`、真正的解壓縮監看和真正的管理者 shell 指令稿（使用替代指令）。

## 致謝

OnePercent 起源於 HaneulKeyboard（하늘키보드）中的更新元件，由同一位作者在這裡通用化。整體流程最初參考了 [exelban/stats](https://github.com/exelban/stats)（MIT）。也從 [Sparkle](https://github.com/sparkle-project/Sparkle)（MIT）、[mxcl/AppUpdater](https://github.com/mxcl/AppUpdater)（Unlicense）、[Squirrel.Mac](https://github.com/Squirrel/Squirrel.Mac)（MIT）中獲得了想法，而不是程式碼。

## 授權條款

MIT — 請參閱 [LICENSE](LICENSE)。Copyright (c) 2026 Hyunjin Cho.
