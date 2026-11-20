import AppKit
import Foundation
import Testing
@testable import OnePercent

/// Runs the administrator script's real shell command against temporary bundles (no administrator rights involved).
/// Failures are injected only at the external-command boundary.
/// 2026-11-20: 하늘키보드 `UpdateReplacementTests`(#176·#226) 를 옮겼다. 안내 문장 대신 종료 코드를 본다.
@Suite @MainActor struct AdminScriptTests {   // NSAppleScript 는 메인 스레드 전용 — 병렬로 부르면 실패했다(2026-11-20)
    let identity = VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.1", build: "200")
    var requirement: String { UpdateDecision.codeRequirement(bundleIdentifier: Fixture.bundleID, team: Fixture.team) }

    nonisolated static let rejections: Set<String> = ["swapped-id", "swapped-version", "swapped-build", "swapped-signature",
                                          "tampered-after-copy", "linked-copy", "real-codesign", "linked-destination", "unsafe-parent",
                                          "unprotected-folder", "not-this-app"]
    nonisolated static let successes: Set<String> = ["real", "modes", "acl", "cleanup", "sticky-parent", "private-tmp", "backup-swapped",
                                         "backup-link", "swapped-before-backup"]
    nonisolated static let steps = ["real", "modes", "acl", "copy", "backup", "place", "restore", "occupied", "cleanup",
                        "sticky-parent", "private-tmp", "prestaged", "raced-place", "backup-swapped"] + rejections.sorted()

    func writeBundle(_ url: URL, version: String, identity: VerifiedIdentity) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try version.write(to: url.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        let info = ["CFBundleIdentifier": identity.bundleID, "CFBundleShortVersionString": identity.version, "CFBundleVersion": identity.build]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
        let code = url.appendingPathComponent("Contents/MacOS/app")
        try Data("code".utf8).write(to: code)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: code.path)
    }

    func mode(_ url: URL) -> mode_t? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info.st_mode & 0o7777 : nil
    }

    func version(_ url: URL) -> String? { try? String(contentsOf: url.appendingPathComponent("version"), encoding: .utf8) }

    func aclListing(_ url: URL) -> String {
        let list = Process(); let out = Pipe()
        list.executableURL = URL(fileURLWithPath: "/bin/ls")
        list.arguments = ["-ledR", url.path, url.appendingPathComponent("Contents").path,
                          url.appendingPathComponent("Contents/MacOS").path, url.appendingPathComponent("Contents/MacOS/app").path]
        list.standardOutput = out; list.standardError = FileHandle.nullDevice
        guard (try? list.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        list.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test(arguments: steps) func step(_ step: String) throws {
        let fm = FileManager.default
        let root = try Fixture.temporaryRoot("admin-\(step)")
        defer { try? fm.removeItem(at: root) }
        // 경로에 셸 특수문자를 넣어 인용을 시험한다.
        let name = "하늘 ' \" $HOME $(touch injected) `touch injected2`\n.app"
        var stagingParent = root
        if step == "unsafe-parent" || step == "sticky-parent" {
            stagingParent = root.appendingPathComponent(step == "unsafe-parent" ? "open" : "sticky")
            try fm.createDirectory(at: stagingParent, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: step == "unsafe-parent" ? 0o777 : 0o1777], ofItemAtPath: stagingParent.path)
        }
        let staging = step == "private-tmp" ? AdminReplacementScript.privateStaging(bundleID: Fixture.bundleID, token: UUID().uuidString)
            : stagingParent.appendingPathComponent(".stage \(name)")
        defer { if step == "private-tmp" { try? fm.removeItem(at: staging) } }
        let script = AdminReplacementScript(source: root.appendingPathComponent("new \(name)"), destination: root.appendingPathComponent(name),
                                            staging: staging, backup: root.appendingPathComponent(".backup \(name)"),
                                            identity: identity, requirement: requirement)
        if step == "prestaged" {
            try fm.createDirectory(at: script.staging, withIntermediateDirectories: true)
            try Data("planted".utf8).write(to: script.staging.appendingPathComponent("planted"))
        }
        var incoming = identity
        switch step {
        case "swapped-id": incoming = VerifiedIdentity(bundleID: "com.example.other", version: identity.version, build: identity.build)
        case "swapped-version": incoming = VerifiedIdentity(bundleID: identity.bundleID, version: "1.0", build: identity.build)
        case "swapped-build": incoming = VerifiedIdentity(bundleID: identity.bundleID, version: identity.version, build: "100")
        default: break
        }
        try writeBundle(script.source, version: "new", identity: incoming)
        if step == "acl" {
            let code = script.source.appendingPathComponent("Contents/MacOS/app")
            for (path, rights) in [(code.path, "write,delete,append,writeattr,writeextattr"),
                                   (code.deletingLastPathComponent().path, "add_file,add_subdirectory,delete_child"),
                                   (script.source.path, "add_file,add_subdirectory,delete_child")] {
                #expect(Fixture.tool("/bin/chmod", ["+a", "user:\(NSUserName()) allow \(rights)", path]) == 0)
            }
        }
        if step == "linked-destination" {
            let target = root.appendingPathComponent("linked-target.app")
            try writeBundle(target, version: "old", identity: identity)
            try fm.createSymbolicLink(at: script.destination, withDestinationURL: target)
        } else if step == "not-this-app" {
            try writeBundle(script.destination, version: "old", identity: VerifiedIdentity(bundleID: "com.example.other", version: "1.0", build: "1"))
        } else {
            try writeBundle(script.destination, version: "old", identity: identity)
        }
        let other = root.appendingPathComponent("Other.app")
        try writeBundle(other, version: "other-app", identity: VerifiedIdentity(bundleID: "com.example.other", version: "9", build: "9"))
        let protected = root.appendingPathComponent("protected")
        if step == "backup-link" {
            // 보안 리뷰 재현 A: 백업 이름 자리에 보호 폴더를 가리키는 링크를 미리 심는다.
            try fm.createDirectory(at: protected, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: script.backup, withDestinationURL: protected)
        }
        let copy = root.appendingPathComponent("copy.sh"), move = root.appendingPathComponent("move.sh")
        let remove = root.appendingPathComponent("remove.sh"), codesign = root.appendingPathComponent("codesign.sh")
        let modeLog = root.appendingPathComponent("staging-mode.log"), codesignLog = root.appendingPathComponent("codesign.log")
        let stubs = [
            (copy, """
            #!/bin/sh
            /usr/bin/stat -f %Lp "$(/usr/bin/dirname "$2")" > "$OP_TEST_MODE_LOG"
            case "$OP_TEST_STEP" in
            copy) /bin/mkdir -p "$2"; printf partial > "$2/version"; exit 71 ;;
            tampered-after-copy) /usr/bin/ditto "$1" "$2" || exit 1; printf evil > "$2/Contents/Info.plist"; exit 0 ;;
            linked-copy) /bin/ln -s "$1" "$2"; exit 0 ;;
            modes) /usr/bin/ditto "$1" "$2" || exit 1; /bin/chmod 6775 "$2/Contents/MacOS/app"; exit 0 ;;
            esac
            exec /usr/bin/ditto "$@"
            """),
            (move, """
            #!/bin/sh
            if [ "$1" = "-h" ]; then shift; fi
            if [ "$OP_TEST_STEP" = backup ] && [ "$2" = "$OP_TEST_BACKUP" ]; then exit 72; fi
            if { [ "$OP_TEST_STEP" = place ] || [ "$OP_TEST_STEP" = restore ] || [ "$OP_TEST_STEP" = occupied ]; } && [ "$1" = "$OP_TEST_STAGE" ]; then
                if [ "$OP_TEST_STEP" = occupied ]; then /bin/mkdir -p "$2"; printf other > "$2/version"; fi
                exit 73
            fi
            if [ "$OP_TEST_STEP" = restore ] && [ "$1" = "$OP_TEST_BACKUP" ]; then exit 74; fi
            if [ "$OP_TEST_STEP" = raced-place ] && [ "$1" = "$OP_TEST_STAGE" ]; then /bin/mkdir -p "$2"; printf other > "$2/version"; fi
            if [ "$OP_TEST_STEP" = backup-swapped ] && [ "$1" = "$OP_TEST_BACKUP" ] && [ "$2" = "$OP_TEST_RETIRED" ]; then
                /bin/mv "$1" "$1.real"; /bin/mkdir -p "$1"; printf foreign > "$1/version"
            fi
            exec /bin/mv -h "$@"
            """),
            (remove, """
            #!/bin/sh
            if [ "$OP_TEST_STEP" = cleanup ] && [ "$2" = "$OP_TEST_STAGING" ]; then exit 75; fi
            exec /bin/rm "$@"
            """),
            (codesign, """
            #!/bin/sh
            printf '%s\\n' "$@" >> "$OP_TEST_CODESIGN_LOG"
            if [ "$OP_TEST_STEP" = swapped-before-backup ] && [ ! -e "$OP_TEST_DEST.real" ]; then
                # 검증하는 동안 같은 사용자가 설치 위치의 옛 앱을 치우고 다른 앱(같은 폴더의 무관한 앱)을 그 자리에 놓는다.
                /bin/mv "$OP_TEST_DEST" "$OP_TEST_DEST.real"; /bin/mv "$OP_TEST_OTHER" "$OP_TEST_DEST"
            fi
            if [ "$OP_TEST_STEP" = swapped-signature ]; then exit 3; fi
            exit 0
            """),
        ]
        for (url, text) in stubs {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        var commands: AdminReplacementScript.Commands = switch step {
        case "real", "acl", "sticky-parent", "private-tmp", "backup-link": .init(codesign: codesign.path)
        case "real-codesign": .init()
        default: .init(copy: copy.path, move: move.path, remove: remove.path, codesign: codesign.path)
        }
        // 시험은 root 가 아니므로, 보호 폴더의 주인으로 이 사용자를 쓴다. "unprotected-folder" 만 제품 값(root)을 쓴다.
        commands.protectedOwner = step == "unprotected-folder" ? 0 : getuid()
        let command = script.shellCommand(commands: commands)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = root
        task.environment = ProcessInfo.processInfo.environment.merging([
            "OP_TEST_STEP": step, "OP_TEST_STAGE": script.stagedApp.path, "OP_TEST_BACKUP": script.backup.path,
            "OP_TEST_STAGING": script.staging.path, "OP_TEST_RETIRED": script.retiredBackup.path,
            "OP_TEST_MODE_LOG": modeLog.path, "OP_TEST_CODESIGN_LOG": codesignLog.path,
            "OP_TEST_DEST": script.destination.path, "OP_TEST_OTHER": other.path,
        ]) { _, new in new }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        let status = task.terminationStatus

        #expect(version(script.source) == "new", "the verified original is untouched")
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("injected").path)
                && !fm.fileExists(atPath: root.appendingPathComponent("injected2").path), "shell characters in paths are never run")
        if Self.rejections.contains(step) {
            let expected: AdminReplacementScript.Exit = switch step {
            case "unsafe-parent": .stagingUnsafe
            case "unprotected-folder", "not-this-app": .destinationUnsafe
            default: .copyChanged
            }
            #expect(status == expected.rawValue, "\(step): \(status) \(output)")
            #expect(version(script.destination) == "old" && mode(script.backup) == nil && mode(script.staging) == nil)
            if step == "linked-destination" {
                #expect((try? fm.destinationOfSymbolicLink(atPath: script.destination.path)) != nil, "a linked destination is not followed")
            }
        } else if step == "prestaged" {
            #expect(status != 0 && version(script.destination) == "old")
            #expect((try? Data(contentsOf: script.staging.appendingPathComponent("planted"))) == Data("planted".utf8)
                    && mode(script.stagedApp) == nil && mode(script.backup) == nil, "someone else's staging is left alone")
        } else if Self.successes.contains(step) {
            #expect(status == 0 && version(script.destination) == "new", "\(step): \(status) \(output)")
            switch step {
            case "cleanup":
                #expect(version(script.retiredBackup) == "old" && output.contains("backup-cleanup-failed"))
                #expect(mode(script.backup) == nil)
            case "backup-swapped":
                #expect(version(script.backup) == "foreign" && output.contains("backup-cleanup-failed"), "a swapped-in folder is put back, not deleted")
                #expect(version(URL(fileURLWithPath: script.backup.path + ".real")) == "old")
            case "backup-link":
                #expect(((try? fm.contentsOfDirectory(atPath: protected.path)) ?? ["?"]).isEmpty, "nothing was moved into the linked folder (mv -h)")
            case "swapped-before-backup":
                // 보안 리뷰 재현 B: 바꿔 놓인 무관한 앱을 옛 앱으로 알고 지우지 않는다.
                #expect(version(script.backup) == "other-app" && output.contains("backup-cleanup-failed"), "\(output)")
            case "acl":
                #expect(aclListing(script.source).contains(" allow "), "premise: the source has ACLs")
                #expect(!aclListing(script.destination).contains(" allow "), "no ACL survives on the placed app")
            case "modes":
                #expect(mode(script.backup) == nil && mode(script.staging) == nil)
                #expect((try? String(contentsOf: modeLog, encoding: .utf8))?.hasPrefix("700") == true, "staging is owner-only before copying")
                #expect(mode(script.destination.appendingPathComponent("Contents/MacOS/app")) == 0o755, "setuid/setgid/group-write removed")
            default:
                #expect(mode(script.backup) == nil && mode(script.staging) == nil)
                let log = (try? String(contentsOf: codesignLog, encoding: .utf8)) ?? ""
                let lines = log.components(separatedBy: "\n")
                #expect(log.contains(script.stagedApp.path) && !log.contains(script.source.path), "the elevated copy is what gets checked")
                #expect(lines.contains("-R=" + requirement), "the same requirement as every other check")
                #expect(["--verify", "--deep", "--strict", "--all-architectures"].allSatisfy(lines.contains))
                var error: NSDictionary?
                let roundTrip = NSAppleScript(source: "return \(AdminReplacementScript.appleScriptLiteral(command))")?.executeAndReturnError(&error)
                #expect(error == nil && roundTrip?.stringValue == command, "AppleScript literal round trip")
                #expect(NSAppleScript(source: script.appleScriptSource)?.compileAndReturnError(&error) == true && error == nil, "the real script compiles")
                let real = script.shellCommand()
                let order = ["/usr/bin/codesign", "/bin/chmod -R u-s,g-s,go-w", "/bin/chmod -RN", "/usr/sbin/chown -hR", "-h \"$destination\" \"$backup\""]
                    .map { real.range(of: $0)?.lowerBound }
                #expect(!order.contains(nil) && zip(order, order.dropFirst()).allSatisfy { $0! < $1! }, "verify → strip modes → owner → swap")
                let setup = ["pinfo=", "[ -k \"$sparent\" ]", "/bin/mkdir -m 700 \"$staging\"", "\"$(/usr/bin/id -u):700\"", "/usr/bin/stat -f %d \"$staging\"",
                             "\"$source\" \"$staged\"", "staged_id=", "backup-mismatch", "-h \"$staged\" \"$destination\"", "= \"$staged_id\"",
                             "-h \"$backup\" \"$retired\"", "\"$retired\")\" = \"$previous_id\""]
                    .map { real.range(of: $0)?.lowerBound }
                #expect(!setup.contains(nil) && zip(setup, setup.dropFirst()).allSatisfy { $0! < $1! })
                #expect(!real.contains("-rf \"$backup\""), "the backup in the app folder is never removed directly as root")
            }
        } else {
            #expect(status != 0, "\(step)")
            switch step {
            case "raced-place":
                #expect(status == AdminReplacementScript.Exit.placeAndRestoreFailed.rawValue)
                #expect(version(script.backup) == "old" && version(script.destination) == "other", "a raced folder is not overwritten")
            case "restore", "occupied":
                #expect(status == AdminReplacementScript.Exit.placeAndRestoreFailed.rawValue)
                #expect(version(script.backup) == "old" && version(script.stagedApp) == "new" && mode(script.staging) == 0o700)
                #expect(version(script.destination) == (step == "occupied" ? "other" : nil))
            case "place":
                #expect(status == AdminReplacementScript.Exit.placeFailedRestored.rawValue && version(script.destination) == "old")
                #expect(mode(script.backup) == nil && mode(script.staging) == nil)
            default:
                #expect(version(script.destination) == "old" && mode(script.backup) == nil && mode(script.staging) == nil, "\(step)")
            }
        }
    }

    @Test func exitCodesBecomeErrors() {
        let script = AdminReplacementScript(source: URL(fileURLWithPath: "/tmp/a.app"), destination: URL(fileURLWithPath: "/Applications/TestApp.app"),
                                            staging: URL(fileURLWithPath: "/private/tmp/s"), backup: URL(fileURLWithPath: "/Applications/.TestApp.app.old-1"),
                                            identity: identity, requirement: requirement)
        #expect(script.error(status: 77, message: "") == .copyChanged)
        #expect(script.error(status: 78, message: "") == .stagingUnsafe)
        #expect(script.error(status: 79, message: "") == .placeFailedRestored)
        #expect(script.error(status: 80, message: "x") == .replaceRecoveryFailed(reason: "x", backupPath: "/Applications/.TestApp.app.old-1",
                                                                                  destinationPath: "/Applications/TestApp.app"))
        #expect(script.error(status: 1, message: "boom") == .replaceFailed("boom"))
        let recovery = OnePercentError.replaceRecoveryFailed(reason: "r", backupPath: "/tmp/backup.app", destinationPath: "/tmp/original.app")
            .message(L10n.table("en"))
        #expect(recovery.contains("/tmp/backup.app") && recovery.contains("/tmp/original.app") && recovery.contains("Finder"))
    }

    @Test func productionStagingIsUnderPrivateTmp() {
        let staging = AdminReplacementScript.privateStaging(bundleID: Fixture.bundleID, token: "fixture")
        var info = stat()
        #expect(staging.deletingLastPathComponent().path == "/private/tmp")
        #expect(lstat("/private/tmp", &info) == 0 && info.st_uid == 0 && info.st_mode & S_ISVTX != 0 && info.st_mode & S_IFMT == S_IFDIR)
    }
}
