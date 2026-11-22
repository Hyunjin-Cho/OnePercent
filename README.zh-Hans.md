# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · [日本語](README.ja.md) · **简体中文** · [繁體中文](README.zh-Hant.md)

> **基准日：** 2026-11-22 · 0.1.0 · 需要管理员密码的安装在真机上验证之前默认关闭。

<!-- README.md（韩文·英文）的简体中文版。修改 README.md 时也要同时修改此文件。 -->

为通过 GitHub Releases 分发的 macOS 应用准备的小型应用内更新组件。只有用户点击［安装］时才会下载，并且只有通过你团队的 Developer ID 签名、Apple 公证、Bundle ID、版本号与构建号提升的全部检查，才会替换应用。

## 需要什么

- macOS 14 或更高版本，Swift 6（Xcode 16 或更高版本）
- 使用 **Developer ID** 签名并通过**公证**的应用
- 每个发布：与版本相同的标签（`1.2` — 若为 `v1.2`，设置 `tagPrefix: "v"`）、一个 `<应用名>_<标签>.zip`、提高后的 `CFBundleVersion`
- 更新重新打开应用期间，`applicationShouldTerminate` 不要返回 `.terminateCancel`

## 添加

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", .upToNextMinor(from: "0.1.0"))
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

// 设置界面: await updater.checkNow() · ［安装］按钮: await updater.installAvailableUpdate()
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

通过后，用标签 `1.2` 发布 GitHub Release 并附上 ZIP。

## 注意事项

- 用户无法写入位置的应用，默认不在应用内安装，而是引导用户到发布页面（`allowsAdministratorInstall`，尚未在真机验证 — [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)）。
- 只向 GitHub 发送 HTTPS `GET` 请求。请求头为 `Accept`、`User-Agent` 和固定的 `Accept-Language: en`，不使用 Cookie 和磁盘缓存。

MIT — [LICENSE](LICENSE)
