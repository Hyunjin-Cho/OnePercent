# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · **日本語** · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md)

> **基準日:** 2026-11-20
> **状態:** 最初のバージョン（0.1、まだリリース前）。自動テストはすべて通っています。管理者パスワードが必要なインストールは、実機で確認するまで既定でオフにしています — [既知の制限](#既知の制限) を参照してください。

<!-- 2026-11-20: README.md（韓国語・英語）の日本語版。README.md を直したらこのファイルも一緒に直す。 -->

GitHub Releases で配布する macOS アプリのための、小さなアプリ内アップデート部品です。無料・MIT で、他人のコードは 1 行も入っていません。

**名前の由来:** アップデート部品は、アプリの中で誰も気にしなくていい 1% であるべきです。静かに確認し、すべてを検証し、ユーザーが［インストール］を押したときだけアプリを置き換えます。

## できること

1. **確認** — リポジトリの最新の GitHub リリースを、決めた間隔で、またはユーザーが望んだときに確認します。自動確認は知らせるだけです。ユーザーが［インストール］を押すまで何もダウンロードしません。
2. **ダウンロード** — HTTPS でリリースの ZIP を受け取ります。そのリポジトリのリリースのアドレスだけを受け付け、受信中にサイズを制限し、GitHub が公開している SHA-256 があれば照合します。
3. **展開する前に ZIP を検査** — ZIP の一覧を直接読み、アプリの外のパス、シンボリックリンクの下の項目、コメント、ZIP64、大きすぎるアーカイブを拒否します。そのうえで `ditto` で展開しながら、ディスクにたまった量（拡張属性を含む）・項目数・かかった時間を見張ります。
4. **アプリの検証** — 次のすべてに通ったときだけインストールします。
   - 本物のアプリフォルダで、最上位に `<アプリ名>.app` だけがあり、アプリの外を指すリンクがないこと
   - バンドル ID が同じであること
   - Apple が発行した **Developer ID** 証明書で **自分のチーム** が署名していること — Security.framework（厳格なフラグ）と `codesign --deep --strict` の 2 回、同じコード要件 1 つで確認します。同じチームでも開発用証明書で署名したビルドは拒否します
   - Apple の **公証** を受けていること（`spctl`）
   - バージョンとビルド番号が **両方とも** 今のアプリより大きいこと
   - 案内したそのバージョンであること
5. **古いアプリを先に消さずに置き換え** — ユーザーが所有するアプリは、すぐ隣にコピーして権限を整え、もう一度確認してから一度に置き換えます。ユーザーが書き込めない場所のアプリ（管理者パスワードが必要な場合）は、既定ではアプリ内でインストールせず、リリースページから手動で置き換えるよう案内します（`allowsAdministratorInstall` でオンにできます）。
6. **再起動** — 新しいバージョンを開き、次回の起動時に「アップデートしたばかり」であることをアプリに伝えます。

アップデートが途中で途切れた跡（強制終了、電源断）は、次回の起動時に片付けます。

## 必要なもの

- macOS 14 以降、Swift 6 ツールチェーン（Xcode 16 以降）
- **Developer ID** で署名し、**公証** を受けた GitHub リリース
- リリースごとに、バージョンそのもののタグ（例: `1.2` または `v1.2`）と、`<アプリ名>_<タグ>.zip` という名前の ZIP ファイル 1 つ
- リリースごとに `CFBundleVersion`（ビルド番号）も上げること — 点で区切った数字 1〜4 個、各 18 桁まで（`202611201530` のような日時形式も使えます）
- アップデートがアプリを開き直すとき、アプリが終了を拒まないこと（`applicationShouldTerminate` で `.terminateCancel` を返さない）

## 追加する

Swift Package Manager:

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", branch: "main")
```

そのうえで、アプリのターゲットの依存関係に `"OnePercent"` を入れます。

## 使う

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp",          // GitHub の owner/name
    teamIdentifier: "ABCDE12345",       // Developer ID のチーム
    bundleIdentifier: "com.example.yourapp",
    appName: "YourApp"))                // ZIP の中に YourApp.app

// 起動時に:
if let version = updater.noteLaunch() {
    // `version` にアップデートした後の最初の起動 — 必要なら知らせます:
    // OnePercentText.updated(to: version)
}
updater.onUpdateAvailable = { update in
    // 自分で作った通知を表示します。ここではインストールしません。
}
updater.installGuard = {
    timer.isRunning ? "先にタイマーを止めてください。" : nil   // 止める理由、なければ nil
}
updater.willRelaunch = {
    // 新しいアプリはこのアプリの applicationWillTerminate より先に起動します — 保存はここで行います。
}
updater.startAutomaticChecks()

// 設定画面で:
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()   // 再起動後なら、先に GitHub にもう一度確認してからインストールします
updater.cancel()                         // ダウンロード中・確認中に
```

`OnePercentUpdater` は `@Observable` です。画面は `updater.presentation`（どの行を表示するか、［インストール］・［キャンセル］ボタンを出すか、最後のエラー）を読んで作り、文言は `OnePercentText` に用意されたものを使えます。プレビュー用に `UpdateStatusPresentation` と `AvailableUpdate` を直接作ることもできます。

## リリースを作る

```sh
# 1. いつもどおり YourApp.app をビルドし、Developer ID で署名し、公証を受け、ステープルします。
#    CFBundleShortVersionString と CFBundleVersion の両方を上げます。
# 2. 親フォルダを保ったまま圧縮します:
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. ユーザーの Mac で動くのと同じコードで事前に検査します（前のリリースと比較）:
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
# 4. タグ 1.2 で GitHub リリースを作り、YourApp_1.2.zip を添付します。
```

Finder の［圧縮］で ZIP を作らないでください — `__MACOSX` フォルダが入ることがあり、その ZIP は拒否されます。アプリ名に空白がある場合は、空白のない `assetName` を決めてください — GitHub がアップロードしたファイル名を変えることがあります。`onepercent-check --help` ですべてのオプションを確認できます。

## 設定

必須なのは最初の 4 つだけです。

| 設定 | 既定値 | 意味 |
|---|---|---|
| `repository` | — | GitHub の `owner/name`。下書き・プレリリースでない最新リリースだけを見ます。 |
| `teamIdentifier` | — | 10 文字のチーム ID。ほかの人が署名したファイルは拒否します。 |
| `bundleIdentifier` | — | ダウンロードしたアプリが持つべきバンドル ID。 |
| `appName` | — | `.app` を除いたアプリ名。 |
| `versionScheme` | `.numeric` | バージョンを読んで比べる規則（下記）。 |
| `tagPrefix` | `""` | タグでバージョンの前に付く文字（例: `"v"`）。 |
| `assetName` | `<appName>_<tag>.zip` | タグごとのアセットのファイル名。 |
| `versionSuffixInfoKey` | なし | `CFBundleShortVersionString` の後ろに付ける Info.plist のキー（例: `_hotfix1`）。 |
| `requireBuildIncrease` | `true` | `CFBundleVersion` も上がっているときだけインストールします。 |
| `schedule` | `.monthly` | `.monthly`、`.weekly`、`.daily`、`.every(秒)`（最低 1 時間）、`.manual`。 |
| `automaticChecksByDefault` | `true` | ユーザーがスイッチに触れる前の自動確認の状態。 |
| `installLocation` | `.inPlace` | `.inPlace` は実行中のアプリがどこにあってもその場で置き換え、`.applicationsFolder` は `/Applications/<appName>.app` のときだけインストールします。 |
| `allowsAdministratorInstall` | `false` | 管理者パスワードが必要な場所のアプリもアプリ内でインストールします（実機で確認してからオンにしてください）。 |
| `defaultsKeyPrefix` | `"OnePercent."` | 保存するキーの先頭部分。 |
| `userAgent` | `<appName>/<バージョン>` | `User-Agent` ヘッダー。 |
| `limits` | ダウンロード 500 MiB、展開は 5 万項目・2 GiB・300 秒 | 小さなアプリはもっと絞ってかまいません。 |
| `allowedHosts` | GitHub の API・Web・アセットのホスト | リクエストとリダイレクトが行けるホスト（HTTPS のみ）。 |
| `testRepository` | なし | テスト時に代わりに使うリポジトリ。アプリの `#if DEBUG` の中でだけ設定してください。パッケージもデバッグビルドのときだけ使います。 |

### バージョンの規則

- `.numeric` — `1`、`1.0`、`1.2.3`、`2026.11.17`。足りない桁は 0 とみなします（`1.0` = `1.0.0`）。桁ごとに数値として比べます（`1.10` > `1.9`）。
- `.calendar()` — `YYYY.MM.DD`。番号付きのホットフィックス接尾辞も使えます: `2026.11.17_hotfix2`。
- 自作の規則: `VersionScheme(name: "build") { text in /* [Int] か nil を返します */ }`。

規則が読めないバージョンは、決して新しいものとはみなしません。実行中のアプリのバージョンを規則が読めない場合は、`noteLaunch()` が設定エラーとして知らせます。

## 言語

すべての文言が 29 言語で入っていて、アプリの言語に合わせます: チェコ語、デンマーク語、ドイツ語、ギリシャ語、英語、スペイン語、フィンランド語、フィリピノ語、フランス語、ハンガリー語、インドネシア語、イタリア語、日本語、韓国語、マレー語、ノルウェー語、オランダ語、ポーランド語、ポルトガル語（ブラジル・ポルトガル）、ルーマニア語、ロシア語、スウェーデン語、タイ語、トルコ語、ウクライナ語、ベトナム語、中国語（簡体字・繁体字）。韓国語が原文で、ほかは原文をもとに書きました。

## 外に送るもの

GitHub への HTTPS の `GET` リクエストだけです（リリース情報は `api.github.com`、ZIP は `github.com` とそのアセットホスト）。OnePercent が付けるヘッダーは `Accept`、`User-Agent`、`Accept-Language: en` の 3 つです。言語ヘッダーは固定値なので、ユーザーの言語リストは送られません。Cookie・ディスクキャッシュ・識別子・ユーザーのデータは送りません。GitHub はこのリクエストをほかの Web リクエストと同じように見ます（IP アドレスを含む）。

## 保存する値

`UserDefaults`（または渡したストア）に次を保存します: 自動確認をオンにしているか、最後に成功した確認、インストールできた最新バージョン、最後に知らせたバージョン、最後に起動したバージョン。`OnePercentUpdater.storedKeys(configuration:)` がすべてのキーを返すので、アプリが自分を初期化するときに消せます。

## 既知の制限

- **管理者の経路は既定でオフです。** セキュリティレビューで見つかった問題は直し、代わりのコマンドでテストしましたが、実際のパスワード画面ではまだ試していません。確認リストは [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)（英語）です。
- 管理者の経路をオンにすると、管理者としてのコピー中はアプリのメインスレッドが待ちます（システムのパスワード画面は `NSAppleScript` を通り、これはメインスレッドで動かす必要があります）。
- 新しいアプリが古いアプリより先に開くため、少しのあいだ両方が起動していることがあります。
- 差分アップデート、段階的な配信、別途の EdDSA 署名はありません。真正性は Developer ID、公証、案内したバージョンとの照合に頼っています。

## 開発

```sh
swift test
```

テストはネットワーク、`/Applications`、ユーザー設定に触れません。一時フォルダに偽のアプリを作り、本物の `ditto`、本物の展開の見張り、本物の管理者用シェルスクリプト（代わりのコマンドで）を動かします。

## 謝辞

OnePercent は HaneulKeyboard（하늘키보드）の中のアップデート部品から始まり、同じ作者がここで汎用化しました。全体の流れは最初に [exelban/stats](https://github.com/exelban/stats)（MIT）を参考にしました。[Sparkle](https://github.com/sparkle-project/Sparkle)（MIT）、[mxcl/AppUpdater](https://github.com/mxcl/AppUpdater)（Unlicense）、[Squirrel.Mac](https://github.com/Squirrel/Squirrel.Mac)（MIT）からも、コードではなくアイデアを得ました。

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。Copyright (c) 2026 Hyunjin Cho.
