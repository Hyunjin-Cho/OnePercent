// onepercent-check — checks a release ZIP with the same code the updater runs, before you upload it.
// 2026-11-20. Usage:
//   swift run onepercent-check --zip MyApp_1.2.zip --tag 1.2 --repository you/MyApp --team ABCDE12345 \
//       --bundle-id com.example.myapp --app-name MyApp [--scheme numeric|calendar] [--tag-prefix v] [--no-signature]
import Foundation
import OnePercent

var values: [String: String] = [:]
var flags: Set<String> = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    guard argument.hasPrefix("--") else { FileHandle.standardError.write(Data("unexpected argument \(argument)\n".utf8)); exit(2) }
    let key = String(argument.dropFirst(2))
    if key == "no-signature" { flags.insert(key); continue }
    guard let value = arguments.popFirst() else { FileHandle.standardError.write(Data("missing value for \(argument)\n".utf8)); exit(2) }
    values[key] = value
}
let required = ["zip", "tag", "repository", "team", "bundle-id", "app-name"]
let missing = required.filter { values[$0] == nil }
guard missing.isEmpty else {
    FileHandle.standardError.write(Data("missing: \(missing.map { "--" + $0 }.joined(separator: " "))\n".utf8))
    exit(2)
}
let scheme: VersionScheme = values["scheme"] == "calendar" ? .calendar() : .numeric
let configuration = OnePercentConfiguration(repository: values["repository"]!, teamIdentifier: values["team"]!,
                                            bundleIdentifier: values["bundle-id"]!, appName: values["app-name"]!,
                                            versionScheme: scheme, tagPrefix: values["tag-prefix"] ?? "")
let report = OnePercentReleaseCheck.check(zip: URL(fileURLWithPath: values["zip"]!), tag: values["tag"]!,
                                          configuration: configuration, checkSignature: !flags.contains("no-signature"))
if report.problems.isEmpty {
    print("OK — \(values["app-name"]!) \(report.bundleVersion ?? "?") (build \(report.build ?? "?")) would be accepted.")
    exit(0)
}
for problem in report.problems { print("✗ \(problem)") }
exit(1)
