// swift-tools-version: 6.0
// 2026-11-20: OnePercent — GitHub Releases 로 배포하는 macOS 앱의 앱 안 업데이트 부품.
// 외부 의존성 0개. 하늘키보드(HaneulKeyboard)의 업데이트 코드를 오너가 직접 일반화해 MIT 로 다시 냈다.
import PackageDescription

let package = Package(
    name: "OnePercent",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OnePercent", targets: ["OnePercent"]),
        .executable(name: "onepercent-check", targets: ["onepercent-check"]),
    ],
    targets: [
        .target(
            name: "OnePercent",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "onepercent-check",
            dependencies: ["OnePercent"]
        ),
        .testTarget(
            name: "OnePercentTests",
            dependencies: ["OnePercent"]
        ),
    ]
)
