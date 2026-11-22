// swift-tools-version: 6.0
// 2026-11-22: docs/MANUAL-TEST.md 용 시험 앱(오너 결정 A — 전용 시험 앱). OnePercent 패키지의 일부가 아니다 —
// 이 폴더 바깥의 OnePercent 를 경로로 가져다 쓴다. 앱으로 묶고 서명하는 것은 make-app.sh.
import PackageDescription

let package = Package(
    name: "OnePercentTestApp",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "OnePercent", path: "..")],
    targets: [
        .executableTarget(name: "OnePercentTestApp", dependencies: [.product(name: "OnePercent", package: "OnePercent")])
    ]
)
