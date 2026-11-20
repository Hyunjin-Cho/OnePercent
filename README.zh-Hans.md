# OnePercent

[한국어](README.md#korean) · [English](README.md#english) · [日本語](README.ja.md) · **简体中文** · [繁體中文](README.zh-Hant.md)

> **基准日：** 2026-11-20
> **状态：** 第一个版本（0.1，尚未发布）。自动测试全部通过。需要管理员密码的安装在真机确认之前默认关闭 — 参见[已知限制](#已知限制)。

<!-- 2026-11-20: README.md（韩语·英语）的简体中文版。修改 README.md 时也要同时修改此文件。 -->

一个为通过 GitHub Releases 发布的 macOS 应用准备的小型应用内更新组件。免费、MIT，不含一行第三方代码。

**名字的含义：** 更新组件应该是应用里那 1% 谁都不用操心的部分。它安静地检查、验证一切，只有在用户点按［安装］时才替换应用。

## 它做什么

1. **检查** — 按你设定的间隔，或在用户想要时，检查仓库最新的 GitHub 发布。自动检查只负责通知；在用户点按［安装］之前不会下载任何东西。
2. **下载** — 通过 HTTPS 获取发布的 ZIP。只接受该仓库的发布地址，接收时限制大小，如果 GitHub 公布了 SHA-256 就进行比对。
3. **解压前检查 ZIP** — 直接读取 ZIP 的目录，拒绝应用之外的路径、符号链接下的项目、注释、ZIP64 和过大的压缩包；然后用 `ditto` 解压，同时监视写入磁盘的数据量（含扩展属性）、项目数和耗时。
4. **验证应用** — 以下全部通过才会安装：
   - 是真正的应用文件夹，最上层只有 `<应用名>.app`，没有指向应用之外的链接
   - Bundle ID 相同
   - 由 Apple 签发的 **Developer ID** 证书、**你的团队** 签名 — 用 Security.framework（严格标志）和 `codesign --deep --strict` 检查两次，使用同一条代码要求。即使是同一团队，用开发证书签名的构建也会被拒绝
   - 已通过 Apple **公证**（`spctl`）
   - 版本号和构建号 **都** 高于当前应用
   - 正是通知过的那个版本
5. **不先删除旧应用就完成替换** — 用户拥有的应用会先复制到它旁边、整理权限、再次检查，然后一次性替换。用户无法写入的位置的应用（需要管理员密码时）默认不在应用内安装，而是提示用户从发布页面手动替换（可用 `allowsAdministratorInstall` 开启）。
6. **重新打开** — 打开新版本，并在下次启动时告诉应用"刚刚更新过"。

更新中途中断留下的痕迹（强制退出、断电）会在下次启动时清理。

## 需要什么

- macOS 14 或更高版本，Swift 6 工具链（Xcode 16 或更高版本）
- 用 **Developer ID** 签名并通过 **公证** 的 GitHub 发布
- 每个发布：一个就是版本本身的标签（例如 `1.2` 或 `v1.2`），以及一个名为 `<应用名>_<标签>.zip` 的 ZIP 文件
- 每个发布也要提高 `CFBundleVersion`（构建号）— 用点分隔的 1～4 段数字，每段最多 18 位（`202611201530` 这样的日期时间格式也可以）
- 更新重新打开应用时，应用不能拒绝退出（不要在 `applicationShouldTerminate` 中返回 `.terminateCancel`）

## 添加

Swift Package Manager：

```swift
.package(url: "https://github.com/Hyunjin-Cho/OnePercent.git", branch: "main")
```

然后把 `"OnePercent"` 加入应用目标的依赖项。

## 使用

```swift
import OnePercent

let updater = OnePercentUpdater(configuration: OnePercentConfiguration(
    repository: "you/YourApp",          // GitHub 上的 owner/name
    teamIdentifier: "ABCDE12345",       // Developer ID 团队
    bundleIdentifier: "com.example.yourapp",
    appName: "YourApp"))                // ZIP 里是 YourApp.app

// 启动时：
if let version = updater.noteLaunch() {
    // 更新到 `version` 后的第一次启动 — 需要的话可以告诉用户：
    // OnePercentText.updated(to: version)
}
updater.onUpdateAvailable = { update in
    // 显示你自己的通知。不要在这里安装。
}
updater.installGuard = {
    timer.isRunning ? "请先停止计时器。" : nil   // 阻止的理由，没有就返回 nil
}
updater.willRelaunch = {
    // 新应用会在本应用的 applicationWillTerminate 之前启动 — 需要保存的内容在这里保存。
}
updater.startAutomaticChecks()

// 在设置界面中：
await updater.checkNow(userInitiated: true, showNotice: false)
await updater.installAvailableUpdate()   // 如果是重新启动之后，会先再问一次 GitHub 再安装
updater.cancel()                         // 下载或检查过程中
```

`OnePercentUpdater` 是 `@Observable` 的。界面读取 `updater.presentation`（显示哪一行、是否显示［安装］·［取消］按钮、最近的错误）来构建，文字可以使用 `OnePercentText` 中准备好的内容。预览时也可以自己创建 `UpdateStatusPresentation` 和 `AvailableUpdate`。

## 制作发布

```sh
# 1. 照常构建 YourApp.app，用 Developer ID 签名，进行公证并装订（staple）。
#    同时提高 CFBundleShortVersionString 和 CFBundleVersion。
# 2. 保留父文件夹进行压缩：
ditto -c -k --keepParent YourApp.app YourApp_1.2.zip
# 3. 用与用户 Mac 上运行的相同代码预先检查（与上一个发布比较）：
swift run --package-path /path/to/OnePercent onepercent-check \
    --zip YourApp_1.2.zip --tag 1.2 --repository you/YourApp \
    --team ABCDE12345 --bundle-id com.example.yourapp --app-name YourApp \
    --previous-version 1.1 --previous-build 7
# 4. 用标签 1.2 创建 GitHub 发布，并附上 YourApp_1.2.zip。
```

不要用访达的［压缩］来制作 ZIP — 它可能会加入 `__MACOSX` 文件夹，这样的 ZIP 会被拒绝。如果应用名里有空格，请设定一个不含空格的 `assetName` — GitHub 可能会更改上传文件的名字。用 `onepercent-check --help` 可以查看所有选项。

## 设置

只有前四项是必需的。

| 设置 | 默认值 | 含义 |
|---|---|---|
| `repository` | — | GitHub 的 `owner/name`。只看不是草稿、不是预发布的最新发布。 |
| `teamIdentifier` | — | 10 位团队 ID。其他人签名的文件会被拒绝。 |
| `bundleIdentifier` | — | 下载的应用必须具有的 Bundle ID。 |
| `appName` | — | 去掉 `.app` 的应用名。 |
| `versionScheme` | `.numeric` | 读取和比较版本的规则（见下文）。 |
| `tagPrefix` | `""` | 标签中版本前面的文字（例如 `"v"`）。 |
| `assetName` | `<appName>_<tag>.zip` | 每个标签的资源文件名。 |
| `versionSuffixInfoKey` | 无 | 附加在 `CFBundleShortVersionString` 后面的 Info.plist 键（例如 `_hotfix1`）。 |
| `requireBuildIncrease` | `true` | `CFBundleVersion` 也提高了才安装。 |
| `schedule` | `.monthly` | `.monthly`、`.weekly`、`.daily`、`.every(秒)`（至少 1 小时）、`.manual`。 |
| `automaticChecksByDefault` | `true` | 用户碰开关之前的自动检查状态。 |
| `installLocation` | `.inPlace` | `.inPlace` 无论正在运行的应用在哪里都原地替换；`.applicationsFolder` 只在 `/Applications/<appName>.app` 时安装。 |
| `allowsAdministratorInstall` | `false` | 需要管理员密码的位置的应用也在应用内安装（请在真机确认后再开启）。 |
| `defaultsKeyPrefix` | `"OnePercent."` | 保存的键的前缀。 |
| `userAgent` | `<appName>/<版本>` | `User-Agent` 标头。 |
| `limits` | 下载 500 MiB；解压 5 万个项目、2 GiB、300 秒 | 小型应用可以收得更紧。 |
| `allowedHosts` | GitHub 的 API、网页和资源主机 | 请求和重定向可以到达的主机（仅限 HTTPS）。 |
| `testRepository` | 无 | 测试时代替使用的仓库。只在应用的 `#if DEBUG` 中设定；组件本身也只在调试构建中使用它。 |

### 版本规则

- `.numeric` — `1`、`1.0`、`1.2.3`、`2026.11.17`。缺少的段视为 0（`1.0` = `1.0.0`）。每段按数字比较（`1.10` > `1.9`）。
- `.calendar()` — `YYYY.MM.DD`，也可以带编号的热修复后缀：`2026.11.17_hotfix2`。
- 自定义规则：`VersionScheme(name: "build") { text in /* 返回 [Int] 或 nil */ }`。

规则无法读取的版本绝不会被视为更新的版本。如果规则读不出正在运行的应用的版本，`noteLaunch()` 会报告配置错误。

## 语言

所有文字都有 29 种语言，并跟随应用的语言：捷克语、丹麦语、德语、希腊语、英语、西班牙语、芬兰语、菲律宾语、法语、匈牙利语、印度尼西亚语、意大利语、日语、韩语、马来语、挪威语、荷兰语、波兰语、葡萄牙语（巴西·葡萄牙）、罗马尼亚语、俄语、瑞典语、泰语、土耳其语、乌克兰语、越南语、中文（简体·繁体）。韩语是原文，其余依据原文撰写。

## 对外发送的内容

只有发往 GitHub 的 HTTPS `GET` 请求（发布信息发往 `api.github.com`，ZIP 发往 `github.com` 及其资源主机）。OnePercent 添加的标头只有 `Accept`、`User-Agent`、`Accept-Language: en` 三个。语言标头是固定值，所以不会发送用户的语言列表。不发送 Cookie、磁盘缓存、标识符或用户数据。GitHub 会像对待其他网页请求一样看待这些请求（包括 IP 地址）。

## 保存的值

在 `UserDefaults`（或你传入的存储）中保存：是否开启自动检查、最后一次成功的检查、可安装的最新版本、最后通知过的版本、最后启动的版本。`OnePercentUpdater.storedKeys(configuration:)` 会列出所有键，应用重置自身时可以删除它们。

## 已知限制

- **管理员路径默认关闭。** 安全审查中发现的问题已修复，并用替代命令测试过，但还没有用真正的密码窗口试过。确认清单是 [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)（英文）。
- 开启管理员路径后，在以管理员身份复制期间，应用的主线程会等待（系统密码窗口经过 `NSAppleScript`，而它必须在主线程上运行）。
- 新应用会在旧应用退出前打开，所以可能会有片刻两者同时运行。
- 没有增量更新、分阶段推送或单独的 EdDSA 签名。真实性依靠 Developer ID、公证和与通知版本的比对。

## 开发

```sh
swift test
```

测试不会接触网络、`/Applications` 或用户设置。它们在临时文件夹中创建假的应用，运行真正的 `ditto`、真正的解压监视和真正的管理员 shell 脚本（使用替代命令）。

## 致谢

OnePercent 起源于 HaneulKeyboard（하늘키보드）中的更新组件，由同一作者在这里通用化。整体流程最初参考了 [exelban/stats](https://github.com/exelban/stats)（MIT）。还从 [Sparkle](https://github.com/sparkle-project/Sparkle)（MIT）、[mxcl/AppUpdater](https://github.com/mxcl/AppUpdater)（Unlicense）、[Squirrel.Mac](https://github.com/Squirrel/Squirrel.Mac)（MIT）中获得了想法，而不是代码。

## 许可证

MIT — 参见 [LICENSE](LICENSE)。Copyright (c) 2026 Hyunjin Cho.
