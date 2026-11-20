// onepercent-check — checks a release ZIP with the same code the updater runs, before you upload it.
// 2026-11-20 (PR #1 코드 리뷰 P3-18 반영: 규칙 오타 거부, 이전 릴리스와의 상승 검사, 접미어 키, --help).
import Foundation
import OnePercent

let usage = """
Usage:
  onepercent-check --zip MyApp_1.2.zip --tag 1.2 --repository you/MyApp --team ABCDE12345 \\
                   --bundle-id com.example.myapp --app-name MyApp [options]

Options:
  --scheme numeric|calendar     how versions are read (default numeric)
  --tag-prefix v                text before the version in tags
  --suffix-key KEY              Info.plist key appended to the version (for example a hotfix suffix)
  --previous-version 1.1        the previous release's version …
  --previous-build 7            … and its CFBundleVersion: the ZIP must be newer, as on users' Macs
  --no-signature                skip the Developer ID, codesign and notarization checks
  --help                        show this text
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var values: [String: String] = [:]
var flags: Set<String> = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    guard argument.hasPrefix("--") else { fail("unexpected argument \(argument)") }
    let key = String(argument.dropFirst(2))
    if key == "help" { print(usage); exit(0) }
    if key == "no-signature" { flags.insert(key); continue }
    guard let value = arguments.popFirst(), !value.hasPrefix("--") else { fail("missing value for \(argument)") }
    values[key] = value
}
let known: Set<String> = ["zip", "tag", "repository", "team", "bundle-id", "app-name", "scheme", "tag-prefix", "suffix-key",
                          "previous-version", "previous-build"]
if let unknown = values.keys.first(where: { !known.contains($0) }) { fail("unknown option --\(unknown)") }
let missing = ["zip", "tag", "repository", "team", "bundle-id", "app-name"].filter { values[$0] == nil }
guard missing.isEmpty else { fail("missing: \(missing.map { "--" + $0 }.joined(separator: " "))") }
let scheme: VersionScheme
switch values["scheme"] ?? "numeric" {
case "numeric": scheme = .numeric
case "calendar": scheme = .calendar()
case let other: fail("unknown scheme \(other) (numeric or calendar)")
}
if (values["previous-version"] == nil) != (values["previous-build"] == nil) {
    fail("--previous-version and --previous-build go together")
}
let configuration = OnePercentConfiguration(repository: values["repository"]!, teamIdentifier: values["team"]!,
                                            bundleIdentifier: values["bundle-id"]!, appName: values["app-name"]!,
                                            versionScheme: scheme, tagPrefix: values["tag-prefix"] ?? "",
                                            versionSuffixInfoKey: values["suffix-key"])
let report = OnePercentReleaseCheck.check(zip: URL(fileURLWithPath: values["zip"]!), tag: values["tag"]!,
                                          configuration: configuration, checkSignature: !flags.contains("no-signature"),
                                          previousVersion: values["previous-version"], previousBuild: values["previous-build"])
if report.problems.isEmpty {
    let compared = values["previous-version"].map { " and is newer than \($0) (build \(values["previous-build"]!))" } ?? ""
    print("OK — \(values["app-name"]!) \(report.bundleVersion ?? "?") (build \(report.build ?? "?")) would be accepted\(compared).")
    exit(0)
}
for problem in report.problems { print("✗ \(problem)") }
exit(1)
