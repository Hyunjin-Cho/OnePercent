# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · **日本語** · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md)

> **基準日：** 2026-11-22 · 0.1.0 · 管理者パスワードが必要なインストールは、実機で確認するまで既定でオフです。

<!-- README.md（韓国語・英語）の日本語版。README.md を直したらこのファイルも一緒に直す。 -->

GitHub Releases で配布する macOS アプリのための、小さなアプリ内アップデート部品です。ユーザーが［インストール］を押したときだけダウンロードし、あなたのチームの Developer ID 署名・Apple 公証・バンドル ID・バージョンとビルド番号の上昇をすべて通過した場合にだけアプリを置き換えます。

## 必要なもの

- macOS 14 以降、Swift 6（Xcode 16 以降）
- **Developer ID** で署名し、**公証**を受けたアプリ
- リリースごとに、バージョンと同じタグ（`1.2` — `v1.2` なら `tagPrefix: "v"`）、`<アプリ名>_<タグ>.zip` 1 つ、上げた `CFBundleVersion`
- アップデートがアプリを再起動する間、`applicationShouldTerminate` で `.terminateCancel` を返さないこと

## 追加する

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.0"))
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

// 設定画面: await updater.checkNow() · ［インストール］ボタン: await updater.installAvailableUpdate()
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

通過したら、タグ `1.2` で GitHub リリースを公開し、ZIP を添付します。

## 知っておくこと

- ユーザーが書き込めない場所のアプリは、既定ではアプリ内でインストールせず、リリースページへ案内します（`allowsAdministratorInstall`、実機での確認前 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- GitHub への HTTPS `GET` のみ送ります。ヘッダーは `Accept`・`User-Agent`・固定の `Accept-Language: en` で、Cookie・ディスクキャッシュは使いません。

MIT — [LICENSE](LICENSE)
