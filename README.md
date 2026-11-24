<a id="korean"></a>

# OnePercent

**한국어** · [English](#english) · [日本語](#japanese) · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **기준일:** 2026-11-24 · 0.2.0 · 관리자 암호가 필요한 설치는 실제 Mac에서 확인할 때까지 기본으로 꺼져 있습니다.

GitHub Releases로 배포하는 macOS 앱의 앱 안 업데이트 부품입니다. 사용자가 [설치]를 눌렀을 때만 내려받고, 내 팀의 Developer ID 서명·Apple 공증·번들 ID·버전과 빌드 번호 상승을 모두 통과하고, 이 Mac에서 열 수 있는 버전(최소 macOS·프로세서)일 때만 앱을 바꿉니다.

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
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.2.0"))
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

설정 화면에는 `OnePercentUpdateSection(updater: updater)`를 넣으면 됩니다 — 상태 한 줄, 버전, [지금 확인]·[설치]·[취소] 중 지금 할 일 하나, 진행률, 자동 확인 스위치를 시스템 기본 모양으로 보여 줍니다. 다른 모양은 `updater.presentation`과 `OnePercentText`(29개 언어)로 직접 만듭니다. 다른 설정은 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 문서 주석에 있습니다.

## 릴리스 만들기

```sh
ditto -c -k --norsrc --keepParent YourApp.app YourApp_1.2.zip
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

통과하면 태그 `1.2`로 GitHub 릴리스를 올리고 ZIP을 붙입니다. 앱에서 상한(`limits`)·`assetName`·`requireBuildIncrease`를 바꿨다면 같은 값을 `--max-asset-mb`·`--max-entries`·`--max-unpacked-mb`·`--asset-name`·`--no-build-increase`로 넘겨야 사용자 Mac과 같은 검사가 됩니다(`--help`). 결과에는 이 버전의 최소 macOS와 프로세서도 나옵니다.

- `--norsrc`가 없으면 확장 속성이 `._` 파일로 ZIP에 들어갑니다. OnePercent는 영향이 없지만, 릴리스 페이지에서 받아 `unzip` 같은 다른 도구로 푼 사람의 앱은 서명이 깨집니다 — 검사 도구가 경고합니다. Finder [압축]은 `__MACOSX`가 들어가 거부될 수 있습니다.
- 올리고 1분쯤 지나 `--zip`·`--tag` 대신 `--published`로 한 번 더 돌리면, 앱이 실제로 받을 최신 릴리스를 앱과 같은 코드로 받아 검사합니다.

## 한 번 내보낸 뒤에는

업데이트는 사용자 Mac에 이미 깔린 **옛 버전**이 판단합니다. 그래서 아래를 어기면 이미 나간 앱의 업데이트가 조용히 끊깁니다.

- 저장소(`repository`)·태그 꼴(`tagPrefix`)·자산 이름(`assetName`)·Team ID·번들 ID는 바꾸지 않습니다.
- GitHub의 최신 릴리스는 늘 이 앱의 정식 릴리스여야 합니다. 초안·프리릴리스는 보지 않고, 다른 파일만 붙은 릴리스가 최신이면 "설치 파일이 준비되지 않았어요"가 계속됩니다.
- 상한(`limits`)은 늘리기만 합니다 — 옛 버전은 옛 상한으로 새 ZIP을 봅니다.
- 최소 macOS를 올리거나 프로세서를 빼기 전에, OnePercent 0.2.0 이상을 쓴 버전이 먼저 나가 있어야 합니다. 그보다 옛 버전은 열리지 않는 새 버전도 그대로 설치합니다.

## 알아 둘 것

- 사용자가 쓸 수 없는 위치의 앱은 기본으로 앱 안에서 설치하지 않고 릴리스 페이지로 안내합니다(`allowsAdministratorInstall`, 실제 Mac 확인 전 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- GitHub로 HTTPS `GET`만 보냅니다. 헤더는 `Accept`·`User-Agent`·고정 `Accept-Language: en`이고, 쿠키·디스크 캐시는 쓰지 않습니다. 리디렉션은 `github.com`·`api.github.com`·`*.githubusercontent.com`(`allowedHosts`)으로만 따라갑니다.
- 화면에 나오는 오류 문장 끝 괄호 안의 코드(예: `(rateLimited)`, `(verificationFailed: notarizationRejected)`)는 모든 언어에서 같습니다 — 사용자의 화면 캡처로 원인을 찾을 때 씁니다.
- 문구 묶음 `OnePercent_OnePercent.bundle`은 `Contents/Resources`, 앱 바로 옆, 실행 파일 옆에서 찾습니다. Xcode 앱 타깃은 알아서 넣고, `.app`을 직접 묶을 때는 `Contents/Resources`에 넣으면 됩니다. 어디에도 없으면 영어로 보여 줍니다(0.1.x는 이때 앱이 꺼졌습니다).

MIT — [LICENSE](LICENSE)

---

---

<a id="english"></a>

# OnePercent — English

[한국어](#korean) · **English** · [日本語](#japanese) · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **As of:** 2026-11-24 · 0.2.0 · Installs that need an administrator password are off by default until tried on a real Mac.

A small in-app updater for macOS apps that ship through GitHub Releases. It downloads only when the user presses Install, and replaces the app only if the download passes every check — your Team's Developer ID signature, Apple notarization, bundle ID, a higher version and build number — and can open on this Mac (minimum macOS, processor).

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
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.2.0"))
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

For your settings, `OnePercentUpdateSection(updater: updater)` is ready to use: a status line, the versions, the one next step (Check Now, Install or Cancel), progress and the automatic-check switch, in the system's own look. For a different look, build your own from `updater.presentation` and `OnePercentText` (29 languages). Other settings are documented in [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift).

## Making a release

```sh
ditto -c -k --norsrc --keepParent YourApp.app YourApp_1.2.zip
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

If it passes, publish a GitHub release with tag `1.2` and attach the ZIP. If your app changes `limits`, `assetName` or `requireBuildIncrease`, pass the same values (`--max-asset-mb`, `--max-entries`, `--max-unpacked-mb`, `--asset-name`, `--no-build-increase`) so the check matches users' Macs (`--help`). It also prints the version's minimum macOS and processors.

- Without `--norsrc`, extended attributes go into the ZIP as `._` files. OnePercent is not affected, but people who download the ZIP and open it with another tool such as `unzip` get an app with a broken signature — the checker warns about it. Finder's Compress can add `__MACOSX`, which is refused.
- About a minute after publishing, run it again with `--published` instead of `--zip` and `--tag`: it fetches the latest release exactly the way apps do and checks what they will get.

## Once a version is out

Updates are judged by the **old version** already on users' Macs. Break one of these and the apps already out stop updating, without a word.

- Never change the repository, the tag form (`tagPrefix`), the asset name (`assetName`), the Team ID or the bundle ID.
- The latest GitHub release must always be this app's real release. Drafts and pre-releases are ignored; if the latest release carries other files only, apps keep saying the installer isn't ready.
- Only ever raise `limits` — old versions judge a new ZIP by their own limits.
- Before raising the minimum macOS or dropping a processor, have a version with OnePercent 0.2.0 or later out first. Older versions install a new version even when it cannot open.

## Good to know

- An app in a place the user cannot write is not installed in-app by default; the user is pointed to the release page (`allowsAdministratorInstall`, untested on a real Mac — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)).
- Only HTTPS `GET` requests to GitHub. Headers: `Accept`, `User-Agent`, fixed `Accept-Language: en`. No cookies, no disk cache. Redirects are followed only to `github.com`, `api.github.com` and `*.githubusercontent.com` (`allowedHosts`).
- The code in brackets at the end of a shown error (for example `(rateLimited)`, `(verificationFailed: notarizationRejected)`) is the same in every language — read it off a user's screenshot.
- The text bundle `OnePercent_OnePercent.bundle` is looked for in `Contents/Resources`, next to the app and next to the executable. Xcode app targets put it there for you; if you put the `.app` together yourself, copy it into `Contents/Resources`. If it is nowhere, the text is English (0.1.x crashed instead).

MIT — [LICENSE](LICENSE)

---

<a id="japanese"></a>

# OnePercent — 日本語

[한국어](#korean) · [English](#english) · **日本語** · [简体中文](#chinese-simplified) · [繁體中文](#chinese-traditional)

> **基準日：** 2026-11-24 · 0.2.0 · 管理者パスワードが必要なインストールは、実機で確認するまで既定でオフです。

GitHub Releases で配布する macOS アプリのための、小さなアプリ内アップデート部品です。ユーザーが［インストール］を押したときだけダウンロードし、あなたのチームの Developer ID 署名・Apple 公証・バンドル ID・バージョンとビルド番号の上昇をすべて通過し、この Mac で開けるバージョン（最小 macOS・プロセッサ）の場合にだけアプリを置き換えます。

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
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.2.0"))
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

設定画面には `OnePercentUpdateSection(updater: updater)` を置くだけで使えます — 状態の 1 行、バージョン、［今すぐ確認］・［インストール］・［キャンセル］のうち今できる 1 つ、進行状況、自動確認のスイッチを、システム標準の見た目で表示します。別の見た目にしたい場合は `updater.presentation` と `OnePercentText`（29 言語）で作ります。その他の設定は [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) のドキュメントコメントにあります。

## リリースを作る

```sh
ditto -c -k --norsrc --keepParent YourApp.app YourApp_1.2.zip
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通過したら、タグ `1.2` で GitHub リリースを公開し、ZIP を添付します。アプリで上限（`limits`）・`assetName`・`requireBuildIncrease` を変えている場合は、同じ値を `--max-asset-mb`・`--max-entries`・`--max-unpacked-mb`・`--asset-name`・`--no-build-increase` で渡すと、ユーザーの Mac と同じ検査になります（`--help`）。結果には、このバージョンの最小 macOS とプロセッサも表示されます。

- `--norsrc` がないと、拡張属性が `._` ファイルとして ZIP に入ります。OnePercent には影響しませんが、リリースページからダウンロードして `unzip` など別のツールで展開した人のアプリは署名が壊れます — 検査ツールが警告します。Finder の［圧縮］は `__MACOSX` が入り、拒否されることがあります。
- 公開して 1 分ほど経ったら、`--zip`・`--tag` の代わりに `--published` でもう一度実行してください。アプリと同じコードで最新リリースを取得し、アプリが実際に受け取るものを検査します。

## 一度公開したら

アップデートを判断するのは、ユーザーの Mac にすでに入っている**古いバージョン**です。次のどれかを破ると、公開済みのアプリは何も言わずにアップデートできなくなります。

- リポジトリ（`repository`）・タグの形（`tagPrefix`）・アセット名（`assetName`）・Team ID・バンドル ID は変えません。
- GitHub の最新リリースは、常にこのアプリの正式リリースにします。ドラフトとプレリリースは見ません。別のファイルだけが付いたリリースが最新だと、「インストールファイルはまだ準備できていません」が続きます。
- 上限（`limits`）は上げるだけにします — 古いバージョンは自分の上限で新しい ZIP を判断します。
- 最小 macOS を上げたりプロセッサを外したりする前に、OnePercent 0.2.0 以降を使ったバージョンを先に公開しておきます。それより古いバージョンは、開けない新バージョンもそのままインストールします。

## 知っておくこと

- ユーザーが書き込めない場所のアプリは、既定ではアプリ内でインストールせず、リリースページへ案内します（`allowsAdministratorInstall`、実機での確認前 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- GitHub への HTTPS `GET` のみ送ります。ヘッダーは `Accept`・`User-Agent`・固定の `Accept-Language: en` で、Cookie・ディスクキャッシュは使いません。リダイレクトは `github.com`・`api.github.com`・`*.githubusercontent.com`（`allowedHosts`）にだけ従います。
- 表示されるエラー文の末尾の括弧内のコード（例：`(rateLimited)`、`(verificationFailed: notarizationRejected)`）は、すべての言語で同じです — ユーザーのスクリーンショットから原因を探すときに使います。
- 文言バンドル `OnePercent_OnePercent.bundle` は `Contents/Resources`、アプリのすぐ隣、実行ファイルの隣で探します。Xcode のアプリターゲットは自動で入れます。`.app` を自分で組み立てる場合は `Contents/Resources` に入れてください。どこにもなければ英語で表示します（0.1.x ではアプリが終了していました）。

MIT — [LICENSE](LICENSE)

---

<a id="chinese-simplified"></a>

# OnePercent — 简体中文

[한국어](#korean) · [English](#english) · [日本語](#japanese) · **简体中文** · [繁體中文](#chinese-traditional)

> **基准日：** 2026-11-24 · 0.2.0 · 需要管理员密码的安装在真机上验证之前默认关闭。

为通过 GitHub Releases 分发的 macOS 应用准备的小型应用内更新组件。只有用户点击［安装］时才会下载，并且只有通过你团队的 Developer ID 签名、Apple 公证、Bundle ID、版本号与构建号提升的全部检查，而且能在这台 Mac 上打开（最低 macOS、处理器）时，才会替换应用。

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
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.2.0"))
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

设置界面里放上 `OnePercentUpdateSection(updater: updater)` 即可 — 以系统默认外观显示状态行、版本、［立即检查］／［安装］／［取消］中当前可做的一项、进度和自动检查开关。需要别的外观时，用 `updater.presentation` 和 `OnePercentText`（29 种语言）自己构建。其他设置见 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 的文档注释。

## 制作发布

```sh
ditto -c -k --norsrc --keepParent YourApp.app YourApp_1.2.zip
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通过后，用标签 `1.2` 发布 GitHub Release 并附上 ZIP。如果应用改了上限（`limits`）、`assetName` 或 `requireBuildIncrease`，请用 `--max-asset-mb`、`--max-entries`、`--max-unpacked-mb`、`--asset-name`、`--no-build-increase` 传入相同的值，检查才与用户的 Mac 一致（`--help`）。结果中还会显示这个版本的最低 macOS 和处理器。

- 不加 `--norsrc` 时，扩展属性会以 `._` 文件进入 ZIP。OnePercent 不受影响，但从发布页面下载并用 `unzip` 等其他工具解压的人，得到的应用签名会损坏 — 检查工具会给出警告。Finder 的［压缩］可能加入 `__MACOSX` 而被拒绝。
- 发布约一分钟后，用 `--published` 代替 `--zip` 和 `--tag` 再运行一次：它用与应用相同的代码获取最新发布，检查应用实际会收到的内容。

## 发布之后

更新由用户 Mac 上已经安装的**旧版本**来判断。违反下面任何一条，已经发出去的应用会悄无声息地无法更新。

- 不要更改仓库（`repository`）、标签形式（`tagPrefix`）、资源名称（`assetName`）、Team ID 和 Bundle ID。
- GitHub 上的最新发布必须始终是这个应用的正式发布。草稿和预发布不会被看到；如果最新发布只附带其他文件，应用会一直提示安装文件尚未准备好。
- 上限（`limits`）只能调高 — 旧版本用自己的上限判断新的 ZIP。
- 在提高最低 macOS 或去掉某个处理器之前，先发布一个使用 OnePercent 0.2.0 或更高版本的版本。更旧的版本会照样安装无法打开的新版本。

## 注意事项

- 用户无法写入位置的应用，默认不在应用内安装，而是引导用户到发布页面（`allowsAdministratorInstall`，尚未在真机验证 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 发送 HTTPS `GET` 请求。请求头为 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 和磁盘缓存。重定向只跟随到 `github.com`、`api.github.com` 和 `*.githubusercontent.com`（`allowedHosts`）。
- 显示的错误句末尾括号里的代码（例如 `(rateLimited)`、`(verificationFailed: notarizationRejected)`）在所有语言中都相同 — 可以从用户的截图中查找原因。
- 文字资源包 `OnePercent_OnePercent.bundle` 会在 `Contents/Resources`、应用旁边和可执行文件旁边查找。Xcode 应用目标会自动放入；自己组装 `.app` 时，请放进 `Contents/Resources`。哪里都找不到时显示英文（0.1.x 在这时会崩溃）。

MIT — [LICENSE](LICENSE)

---

<a id="chinese-traditional"></a>

# OnePercent — 繁體中文

[한국어](#korean) · [English](#english) · [日本語](#japanese) · [简体中文](#chinese-simplified) · **繁體中文**

> **基準日：** 2026-11-24 · 0.2.0 · 需要管理者密碼的安裝在實機驗證之前預設關閉。

為透過 GitHub Releases 發佈的 macOS App 準備的小型 App 內更新元件。只有使用者按下［安裝］時才會下載，並且只有通過你團隊的 Developer ID 簽章、Apple 公證、Bundle ID、版本號與建置號提升的全部檢查，而且能在這台 Mac 上開啟（最低 macOS、處理器）時，才會取代 App。

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
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.2.0"))
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

設定畫面裡放上 `OnePercentUpdateSection(updater: updater)` 即可 — 以系統預設外觀顯示狀態列、版本、［立即檢查］／［安裝］／［取消］中目前可做的一項、進度和自動檢查開關。需要別的外觀時，用 `updater.presentation` 和 `OnePercentText`（29 種語言）自己建構。其他設定見 [`OnePercentConfiguration`](Sources/OnePercent/Configuration.swift) 的文件註解。

## 製作發佈

```sh
ditto -c -k --norsrc --keepParent YourApp.app YourApp_1.2.zip
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
```

通過後，用標籤 `1.2` 發佈 GitHub Release 並附上 ZIP。如果 App 改了上限（`limits`）、`assetName` 或 `requireBuildIncrease`，請用 `--max-asset-mb`、`--max-entries`、`--max-unpacked-mb`、`--asset-name`、`--no-build-increase` 傳入相同的值，檢查才會與使用者的 Mac 一致（`--help`）。結果中也會顯示這個版本的最低 macOS 和處理器。

- 不加 `--norsrc` 時，延伸屬性會以 `._` 檔案進入 ZIP。OnePercent 不受影響，但從發佈頁面下載並用 `unzip` 等其他工具解壓的人，得到的 App 簽章會損壞 — 檢查工具會提出警告。Finder 的［壓縮］可能加入 `__MACOSX` 而被拒絕。
- 發佈約一分鐘後，用 `--published` 取代 `--zip` 和 `--tag` 再執行一次：它用與 App 相同的程式碼取得最新發佈，檢查 App 實際會收到的內容。

## 發佈之後

更新由使用者 Mac 上已經安裝的**舊版本**來判斷。違反下面任何一條，已經發出去的 App 會悄無聲息地無法更新。

- 不要更改儲存庫（`repository`）、標籤形式（`tagPrefix`）、資源名稱（`assetName`）、Team ID 和 Bundle ID。
- GitHub 上的最新發佈必須始終是這個 App 的正式發佈。草稿和預發佈不會被看到；如果最新發佈只附帶其他檔案，App 會一直提示安裝檔尚未準備好。
- 上限（`limits`）只能調高 — 舊版本用自己的上限判斷新的 ZIP。
- 在提高最低 macOS 或拿掉某個處理器之前，先發佈一個使用 OnePercent 0.2.0 或更新版本的版本。更舊的版本會照樣安裝無法開啟的新版本。

## 注意事項

- 使用者無法寫入位置的 App，預設不在 App 內安裝，而是引導使用者到發佈頁面（`allowsAdministratorInstall`，尚未在實機驗證 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 傳送 HTTPS `GET` 請求。標頭為 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 與磁碟快取。重新導向只會跟隨到 `github.com`、`api.github.com` 和 `*.githubusercontent.com`（`allowedHosts`）。
- 顯示的錯誤句末尾括號裡的代碼（例如 `(rateLimited)`、`(verificationFailed: notarizationRejected)`）在所有語言中都相同 — 可以從使用者的截圖中找出原因。
- 文字資源包 `OnePercent_OnePercent.bundle` 會在 `Contents/Resources`、App 旁邊和執行檔旁邊尋找。Xcode App 目標會自動放入；自己組裝 `.app` 時，請放進 `Contents/Resources`。哪裡都找不到時顯示英文（0.1.x 在這時會當掉）。

MIT — [LICENSE](LICENSE)

<!-- 한 판을 고치면 다섯 판(이 파일 안의 5개 섹션)을 같이 고친다. -->
