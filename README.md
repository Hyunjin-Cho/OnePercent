<a id="korean"></a>

# OnePercent

**한국어** · [English](#english) · [日本語](#japanese) · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **기준일:** 2026-11-22 · 0.1.2 · 관리자 암호가 필요한 설치는 실제 Mac에서 확인할 때까지 기본으로 꺼져 있습니다.

GitHub Releases로 배포하는 macOS 앱의 앱 안 업데이트 부품입니다. 사용자가 [설치]를 눌렀을 때만 내려받고, 내 팀의 Developer ID 서명·Apple 공증·번들 ID·버전과 빌드 번호 상승을 모두 통과해야 앱을 바꿉니다.

## 필요한 것

- macOS 14 이상, Swift 6(Xcode 16 이상)
- **Developer ID**로 서명하고 **공증**받은 앱
- **공개** GitHub 저장소 — 로그인 없이 묻기 때문에 비공개 저장소는 "릴리스를 찾을 수 없어요"로 끝납니다
- App Sandbox를 켜지 않은 앱 — 샌드박스 앱은 자기 옆에 새 사본을 놓을 수 없습니다
- 릴리스마다 버전과 같은 태그(`1.2` — `v1.2` 꼴이면 `tagPrefix: "v"`), `<앱이름>_<태그>.zip` 하나, 올린 `CFBundleVersion`
- 앱 이름에 영문·숫자·`.`·`-`·`_` 말고 다른 글자(악센트·한글·공백 등)가 있으면 GitHub가 올린 파일 이름을 바꿉니다 — `assetName`으로 영문 이름을 정하세요
- 업데이트가 앱을 다시 여는 동안 `applicationShouldTerminate`에서 `.terminateCancel`을 돌려주지 않기

## 추가하기

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.2"))
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

// 설정 화면: await updater.checkNow(showNotice: false) · [설치] 버튼: await updater.installAvailableUpdate()
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

통과하면 태그 `1.2`로 GitHub 릴리스를 올리고 ZIP을 붙입니다. 앱에서 상한(`limits`)·`assetName`·`requireBuildIncrease`를 바꿨다면 같은 값을 `--max-asset-mb`·`--max-entries`·`--max-unpacked-mb`·`--asset-name`·`--no-build-increase`로 넘겨야 사용자 Mac과 같은 검사가 됩니다(`--help`).

## 알아 둘 것

- 사용자가 쓸 수 없는 위치의 앱은 기본으로 앱 안에서 설치하지 않고 릴리스 페이지로 안내합니다(`allowsAdministratorInstall`, 실제 Mac 확인 전 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- GitHub로 HTTPS `GET`만 보냅니다. 헤더는 `Accept`·`User-Agent`·고정 `Accept-Language: en`이고, 쿠키·디스크 캐시는 쓰지 않습니다.
- Xcode 앱 타깃은 문구 묶음 `OnePercent_OnePercent.bundle`을 알아서 넣습니다. SwiftPM 실행 파일로 `.app`을 직접 묶는다면 이 묶음을 `Contents/Resources`에 복사하세요 — 없으면 OnePercent 문구를 처음 쓰는 순간 앱이 꺼집니다.

MIT — [LICENSE](LICENSE)

---

---

<a id="english"></a>

# OnePercent — English

[한국어](#korean) · **English** · [日本語](#japanese) · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **As of:** 2026-11-22 · 0.1.2 · Installs that need an administrator password are off by default until tried on a real Mac.

A small in-app updater for macOS apps that ship through GitHub Releases. It downloads only when the user presses Install, and replaces the app only if the download passes every check: your Team's Developer ID signature, Apple notarization, bundle ID, and a higher version and build number.

## Requirements

- macOS 14 or later, Swift 6 (Xcode 16 or later).
- An app signed with **Developer ID** and **notarized**.
- A **public** GitHub repository — OnePercent asks without signing in, so a private one ends in "No release was found".
- No App Sandbox — a sandboxed app cannot place the new copy next to itself.
- Each release: a tag equal to the version (`1.2` — for `v1.2` set `tagPrefix: "v"`), one ZIP named `<YourApp>_<tag>.zip`, and a raised `CFBundleVersion`.
- If your app's name has anything but ASCII letters, digits, `.`, `-` and `_` (accents, Hangul, spaces…), GitHub renames the uploaded file — set `assetName` to a plain name.
- While an update reopens your app, `applicationShouldTerminate` must not return `.terminateCancel`.

## Add it

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.2"))
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

// Settings: await updater.checkNow(showNotice: false) · Install button: await updater.installAvailableUpdate()
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

If it passes, publish a GitHub release with tag `1.2` and attach the ZIP. If your app changes `limits`, `assetName` or `requireBuildIncrease`, pass the same values (`--max-asset-mb`, `--max-entries`, `--max-unpacked-mb`, `--asset-name`, `--no-build-increase`) so the check matches users' Macs (`--help`).

## Good to know

- An app in a place the user cannot write is not installed in-app by default; the user is pointed to the release page (`allowsAdministratorInstall`, untested on a real Mac — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- Only HTTPS `GET` requests to GitHub. Headers: `Accept`, `User-Agent`, fixed `Accept-Language: en`. No cookies, no disk cache.
- Xcode app targets copy the text bundle `OnePercent_OnePercent.bundle` for you. If you put the `.app` together yourself from a SwiftPM executable, copy it into `Contents/Resources` — without it the app crashes the first time it shows OnePercent text.

MIT — [LICENSE](LICENSE)

---

<a id="japanese"></a>

# OnePercent — 日本語

[한국어](#korean) · [English](#english) · **日本語** · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **基準日：** 2026-11-22 · 0.1.2 · 管理者パスワードが必要なインストールは、実機で確認するまで既定でオフです。

GitHub Releases で配布する macOS アプリのための、小さなアプリ内アップデート部品です。ユーザーが［インストール］を押したときだけダウンロードし、あなたのチームの Developer ID 署名・Apple 公証・バンドル ID・バージョンとビルド番号の上昇をすべて通過した場合にだけアプリを置き換えます。

## 必要なもの

- macOS 14 以降、Swift 6（Xcode 16 以降）
- **Developer ID** で署名し、**公証**を受けたアプリ
- **公開**の GitHub リポジトリ — ログインせずに問い合わせるため、非公開リポジトリは「リリースが見つかりません」で終わります
- App Sandbox を使わないアプリ — サンドボックス化したアプリは、自分の隣に新しいコピーを置けません
- リリースごとに、バージョンと同じタグ（`1.2` — `v1.2` なら `tagPrefix: "v"`）、`<アプリ名>_<タグ>.zip` 1 つ、上げた `CFBundleVersion`
- アプリ名に英数字・`.`・`-`・`_` 以外の文字（アクセント・ハングル・空白など）があると GitHub がアップロードしたファイル名を変えます — `assetName` で英数字の名前を指定してください
- アップデートがアプリを再起動する間、`applicationShouldTerminate` で `.terminateCancel` を返さないこと

## 追加する

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.2"))
```

## 使う

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp", teamIdentifier: "ABCDE12345",
    bundleIdentifier: "com.example.yourapp", appName: "YourApp"))

updater.noteLaunch()   // 起動時に 1 回。アップデート直後なら新しいバージョンを返します
updater.onUpdateAvailable = { update in /* 独自の通知を表示。ここではインストールしない */ }
updater.willRelaunch = { /* 保存はここで — 新しいアプリは applicationWillTerminate より先に起動します */ }
updater.startAutomaticChecks()

// 設定画面: await updater.checkNow(showNotice: false) · ［インストール］ボタン: await updater.installAvailableUpdate()
```

画面は `updater.presentation` と `OnePercentText`（29 言語）で作ります。その他の設定は [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) のドキュメントコメントにあります。

## リリースを作る

```sh
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip   # Finder の［圧縮］は __MACOSX が入り、拒否されることがあります
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通過したら、タグ `1.2` で GitHub リリースを公開し、ZIP を添付します。アプリで上限（`limits`）・`assetName`・`requireBuildIncrease` を変えている場合は、同じ値を `--max-asset-mb`・`--max-entries`・`--max-unpacked-mb`・`--asset-name`・`--no-build-increase` で渡すと、ユーザーの Mac と同じ検査になります（`--help`）。

## 知っておくこと

- ユーザーが書き込めない場所のアプリは、既定ではアプリ内でインストールせず、リリースページへ案内します（`allowsAdministratorInstall`、実機での確認前 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- GitHub への HTTPS `GET` のみ送ります。ヘッダーは `Accept`・`User-Agent`・固定の `Accept-Language: en` で、Cookie・ディスクキャッシュは使いません。
- Xcode のアプリターゲットは文言バンドル `OnePercent_OnePercent.bundle` を自動で入れます。SwiftPM の実行ファイルから `.app` を自分で組み立てる場合は、このバンドルを `Contents/Resources` にコピーしてください — ないと OnePercent の文言を初めて表示した瞬間にアプリが終了します。

MIT — [LICENSE](LICENSE)

---

<a id="chinese-simplified"></a>

# OnePercent — 简体中文

[한국어](#korean) · [English](#english) · [日本語](#japanese) · **简体中文** · [繁體中文](#chinese-traditional)

> **基准日：** 2026-11-22 · 0.1.2 · 需要管理员密码的安装在真机上验证之前默认关闭。

为通过 GitHub Releases 分发的 macOS 应用准备的小型应用内更新组件。只有用户点击［安装］时才会下载，并且只有通过你团队的 Developer ID 签名、Apple 公证、Bundle ID、版本号与构建号提升的全部检查，才会替换应用。

## 需要什么

- macOS 14 或更高版本，Swift 6（Xcode 16 或更高版本）
- 使用 **Developer ID** 签名并通过**公证**的应用
- **公开**的 GitHub 仓库 — 检查时不登录，私有仓库只会得到“找不到发布版本”
- 不启用 App Sandbox 的应用 — 沙盒应用无法把新副本放在自己旁边
- 每个发布：与版本相同的标签（`1.2` — 若为 `v1.2`，设置 `tagPrefix: "v"`）、一个 `<应用名>_<标签>.zip`、提高后的 `CFBundleVersion`
- 应用名如果含有英文字母、数字、`.`、`-`、`_` 以外的字符（重音字母、韩文、空格等），GitHub 会改掉上传的文件名 — 请用 `assetName` 指定英文名称
- 更新重新打开应用期间，`applicationShouldTerminate` 不要返回 `.terminateCancel`

## 添加

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.2"))
```

## 使用

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp", teamIdentifier: "ABCDE12345",
    bundleIdentifier: "com.example.yourapp", appName: "YourApp"))

updater.noteLaunch()   // 启动时调用一次。刚更新完时返回新版本
updater.onUpdateAvailable = { update in /* 显示你自己的通知。不要在这里安装 */ }
updater.willRelaunch = { /* 需要保存的内容在这里保存 — 新应用会先于 applicationWillTerminate 启动 */ }
updater.startAutomaticChecks()

// 设置界面: await updater.checkNow(showNotice: false) · ［安装］按钮: await updater.installAvailableUpdate()
```

界面由 `updater.presentation` 和 `OnePercentText`（29 种语言）构建。其他设置见 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 的文档注释。

## 制作发布

```sh
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip   # Finder 的［压缩］可能加入 __MACOSX 而被拒绝
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通过后，用标签 `1.2` 发布 GitHub Release 并附上 ZIP。如果应用改了上限（`limits`）、`assetName` 或 `requireBuildIncrease`，请用 `--max-asset-mb`、`--max-entries`、`--max-unpacked-mb`、`--asset-name`、`--no-build-increase` 传入相同的值，检查才与用户的 Mac 一致（`--help`）。

## 注意事项

- 用户无法写入位置的应用，默认不在应用内安装，而是引导用户到发布页面（`allowsAdministratorInstall`，尚未在真机验证 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 发送 HTTPS `GET` 请求。请求头为 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 和磁盘缓存。
- Xcode 应用目标会自动放入文字资源包 `OnePercent_OnePercent.bundle`。如果你用 SwiftPM 可执行文件自己组装 `.app`，请把它复制到 `Contents/Resources` — 缺少时，应用第一次显示 OnePercent 文字就会崩溃。

MIT — [LICENSE](LICENSE)

---

<a id="chinese-traditional"></a>

# OnePercent — 繁體中文

[한국어](#korean) · [English](#english) · [日本語](#japanese) · [简体中文](#chinese-simplified) · **繁體中文**

> **基準日：** 2026-11-22 · 0.1.2 · 需要管理者密碼的安裝在實機驗證之前預設關閉。

為透過 GitHub Releases 發佈的 macOS App 準備的小型 App 內更新元件。只有使用者按下［安裝］時才會下載，並且只有通過你團隊的 Developer ID 簽章、Apple 公證、Bundle ID、版本號與建置號提升的全部檢查，才會取代 App。

## 需要什麼

- macOS 14 或更新版本，Swift 6（Xcode 16 或更新版本）
- 使用 **Developer ID** 簽章並通過**公證**的 App
- **公開**的 GitHub 儲存庫 — 檢查時不登入，私人儲存庫只會得到「找不到發佈版本」
- 不啟用 App Sandbox 的 App — 沙盒 App 無法把新副本放在自己旁邊
- 每個發佈：與版本相同的標籤（`1.2` — 若為 `v1.2`，設定 `tagPrefix: "v"`）、一個 `<App 名稱>_<標籤>.zip`、提高後的 `CFBundleVersion`
- App 名稱如果含有英文字母、數字、`.`、`-`、`_` 以外的字元（重音字母、韓文、空白等），GitHub 會改掉上傳的檔名 — 請用 `assetName` 指定英文名稱
- 更新重新開啟 App 期間，`applicationShouldTerminate` 不要回傳 `.terminateCancel`

## 加入

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.2"))
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

// 設定畫面: await updater.checkNow(showNotice: false) · ［安裝］按鈕: await updater.installAvailableUpdate()
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

通過後，用標籤 `1.2` 發佈 GitHub Release 並附上 ZIP。如果 App 改了上限（`limits`）、`assetName` 或 `requireBuildIncrease`，請用 `--max-asset-mb`、`--max-entries`、`--max-unpacked-mb`、`--asset-name`、`--no-build-increase` 傳入相同的值，檢查才會與使用者的 Mac 一致（`--help`）。

## 注意事項

- 使用者無法寫入位置的 App，預設不在 App 內安裝，而是引導使用者到發佈頁面（`allowsAdministratorInstall`，尚未在實機驗證 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 傳送 HTTPS `GET` 請求。標頭為 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 與磁碟快取。
- Xcode App 目標會自動放入文字資源包 `OnePercent_OnePercent.bundle`。如果你用 SwiftPM 執行檔自己組裝 `.app`，請把它複製到 `Contents/Resources` — 缺少時，App 第一次顯示 OnePercent 文字就會當掉。

MIT — [LICENSE](LICENSE)

<!-- 한 판을 고치면 다섯 판(이 파일 안의 5개 섹션)을 같이 고친다. -->
