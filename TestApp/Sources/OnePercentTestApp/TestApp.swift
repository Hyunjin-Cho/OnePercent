// OnePercentTestApp — a small app for the real-Mac cases in docs/MANUAL-TEST.md. Not part of the OnePercent package.
//
// It can be driven by hand (buttons) or with launch arguments, so most cases run without anyone at the keyboard:
//   --auto-install         check, then install if an update is there
//   --check-only           check and log the result
//   --cancel-at 0.3        while downloading, press Cancel once the download passes 30 %
//   --allow-admin          allow the administrator-password install for this run
// Every step goes to ~/Library/Logs/OnePercentTestApp.log (one line each: time, process, version, event).
//
// 2026-11-22: 오너 결정(A — 전용 시험 앱). 다시 열린 새 앱은 실행 인자를 물려받지 않는다 — 그래서 첫 실행 기록(noteLaunch)은 늘 남긴다.
import AppKit
import OnePercent
import SwiftUI

@MainActor
enum Probe {
    static let info = Bundle.main.infoDictionary ?? [:]
    static let version = info["CFBundleShortVersionString"] as? String ?? "?"
    static let build = info["CFBundleVersion"] as? String ?? "?"
    static let arguments = Array(CommandLine.arguments.dropFirst())
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OnePercentTestApp.log")

    static func flag(_ name: String) -> Bool { arguments.contains(name) }
    static func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Administrator install: `--allow-admin`, or `defaults write <bundle id> allowAdministratorInstall -bool YES` for runs by hand.
    static let allowsAdministratorInstall = flag("--allow-admin") || UserDefaults.standard.bool(forKey: "allowAdministratorInstall")

    static let configuration: OnePercentConfiguration = {
        var configuration = OnePercentConfiguration(
            repository: info["OPRepository"] as? String ?? "",
            teamIdentifier: info["OPTeamIdentifier"] as? String ?? "",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            appName: "OnePercentTestApp",
            schedule: .manual,
            automaticChecksByDefault: false,
            defaultsKeyPrefix: "OnePercent.")
        configuration.allowsAdministratorInstall = allowsAdministratorInstall
        return configuration
    }()

    static let updater = OnePercentUpdater(configuration: configuration)

    static func log(_ event: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) pid=\(getpid()) v\(version)(\(build)) \(event)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: logURL)
        }
    }

    static func describe(_ phase: OnePercentUpdater.Phase) -> String {
        switch phase {
        case .idle: "idle"
        case .checking: "checking"
        case .upToDate: "upToDate"
        case .available(let update): "available \(update.tag)"
        case .downloading(let fraction): fraction.map { "downloading \(Int($0 * 100))%" } ?? "downloading"
        case .verifying: "verifying"
        case .installing: "installing"
        }
    }

    static func launched() {
        let updated = updater.noteLaunch()
        log("launch path=\(Bundle.main.bundlePath) justUpdatedTo=\(updated ?? "nil") admin=\(allowsAdministratorInstall) "
            + "repository=\(configuration.repository) args=\(arguments.joined(separator: " "))")
        // Case 13: the app's language and one OnePercent string in it.
        log("language=\(Bundle.main.preferredLocalizations.first ?? "?") text=\"\(OnePercentText.checkNow)\"")
        if let updated { log("text: \(OnePercentText.updated(to: updated))") }
        updater.willRelaunch = { log("relaunching") }
        watch()
        if flag("--auto-install") || flag("--check-only") {
            Task {
                await updater.checkNow(userInitiated: true, showNotice: false)
                report("check")
                guard flag("--auto-install"), case .available = updater.phase else { return }
                await updater.installAvailableUpdate()
                report("install returned")   // only reached when it did not reopen
            }
        }
    }

    static func report(_ step: String) {
        let error = updater.presentation.errorText.map { " error=\($0)" } ?? ""
        log("\(step): phase=\(describe(updater.phase)) latest=\(updater.latestVersion ?? "nil")\(error)")
    }

    /// Logs every phase change (download progress in steps of 10 %) and presses Cancel for `--cancel-at`.
    static func watch() {
        Task {
            var last = ""
            var cancelAt = value("--cancel-at").flatMap(Double.init)
            while true {
                var now = describe(updater.phase)
                if case .downloading(let fraction?) = updater.phase {
                    now = "downloading \(Int(fraction * 10) * 10)%"
                    if let threshold = cancelAt, fraction >= threshold {
                        cancelAt = nil
                        log("cancel pressed at \(Int(fraction * 100))%")
                        updater.cancel()
                    }
                }
                if now != last { log("phase \(now)"); last = now }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Probe.launched() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    let updater = Probe.updater

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OnePercentTestApp \(Probe.version) (\(Probe.build))").font(.headline)
            Text(Bundle.main.bundlePath).font(.caption).textSelection(.enabled)
            Text("\(OnePercentText.installedVersion): \(updater.currentVersion) · \(OnePercentText.latestVersion): \(updater.latestVersion ?? OnePercentText.notCheckedYet)")
            if let updated = updater.justUpdatedTo { Text(OnePercentText.updated(to: updated)).foregroundStyle(.green) }
            if let line = updater.presentation.text { Text(line) }
            if let error = updater.presentation.errorText { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(OnePercentText.checkNow) { Task { await updater.checkNow(showNotice: false); Probe.report("check (button)") } }
                if updater.presentation.showsInstallButton {
                    Button(OnePercentText.install) { Task { await updater.installAvailableUpdate(); Probe.report("install returned (button)") } }
                }
                if updater.presentation.showsCancelButton { Button(OnePercentText.cancel) { updater.cancel() } }
            }
            Text("Administrator install: \(Probe.allowsAdministratorInstall ? "on" : "off") · log: ~/Library/Logs/OnePercentTestApp.log")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 460, alignment: .leading)
    }
}

@main
struct OnePercentTestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("OnePercentTestApp") { ContentView() }
    }
}
