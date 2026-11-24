import Foundation

/// Swapping the installed app for the verified one — never deleting the old app first.
///
/// 2026-11-20: 하늘키보드 `Updater.replaceAtomically`·`UpdateReplacementScript` 를 옮겼다. 관리자 스크립트의 한국어 안내는
/// 종료 코드로 바꿨고(문장은 앱 쪽에서 29개 언어로), 강제 종료 때 남는 staging 을 다음 실행에 치우는 정리를 더했다(Fable 리뷰).
enum UpdateReplacement {
    /// Name prefix of the user-path staging copy next to the installed app.
    static func stagingPrefix(for destination: URL) -> String { ".\(destination.lastPathComponent).onepercent-" }

    /// The copy's name inside the staging folder: not ending in `.app`, so macOS does not take it for an app.
    /// `replaceItemAt` gives the result the installed app's own name.
    /// 2026-11-24 (#31) 실측(macOS 27.2.1): `.app` 으로 끝나는 사본은 macOS 가 LaunchServices 에 등록해, 폴더를 지운 뒤에도
    /// 등록이 남았다(`lsregister -gc` 로도 안 지워짐 — 공개 해제 API 없음). 두 경로 —
    /// ① /Applications 감시 데몬이 숨은 폴더 안의 `.app` 을 4초 안에 등록(케이스 7처럼 사본이 오래 남으면 그대로 남음),
    /// ② 등록된 큰 옛 앱을 `replaceItemAt` 으로 바꿀 때 `withItemAt` 경로를 등록(2회 중 2회).
    /// 이름이 `<App>.app.incoming` 이면 둘 다 0건이고, `codesign --deep --strict -R` 재검사도 그대로 통과한다.
    /// 남은 등록이 열기·URL 스킴을 가로채는 일은 재현되지 않았다(DB 잡동사니 수준) — 그래도 남기지 않는다.
    static func stagedCopyName(for destination: URL) -> String { destination.lastPathComponent + ".incoming" }

    static func strategy(for destination: URL) -> UpdateDecision.ReplaceStrategy {
        var info = stat()
        let owner = lstat(destination.path, &info) == 0 ? info.st_uid : nil
        let parentPath = destination.deletingLastPathComponent().path
        var parentInfo = stat()
        let parentOwner = lstat(parentPath, &parentInfo) == 0 ? parentInfo.st_uid : nil
        let parentWritable = FileManager.default.isWritableFile(atPath: parentPath)
        return UpdateDecision.replaceStrategy(destinationOwnerUID: owner, parentOwnerUID: parentOwner,
                                              currentUID: getuid(), parentWritable: parentWritable)
    }

    /// User-owned install: copy to a staging folder on the same volume → re-check the copy → swap with `replaceItemAt`.
    /// If copying or the re-check fails, the installed app is untouched.
    /// 2026-11-13 (하늘키보드 #226 F-9): 임시 폴더의 사본은 검증과 복사 사이에 같은 사용자 권한의 코드가 바꿀 수 있다.
    /// staging 의 복사본이 검증 때 읽은 정체와 같고 서명이 온전할 때만 바꾼다.
    /// 2026-11-22 (#19): staging 은 새로 만든 폴더이고 앱 사본은 그 안에 둔다. 예전엔 앱을 staging 이름으로 바로 복사해,
    /// 사본이 원본(ZIP 에서 푼 앱)의 수정 시각 — 보통 몇 시간 전 — 을 물려받았다. 그래서 교체하는 1~2초 사이에 같은 앱이 또
    /// 실행되면 그쪽 시작 정리(10분 기준)가 진행 중인 사본을 지워 교체가 실패했다(실측: 1시간 전 빌드 → 나이 3601초 → 삭제).
    /// 새로 만든 폴더는 나이가 지금부터 시작하므로 removeLeftovers 의 10분 보호가 이 사본에도 통한다.
    static func replaceAtomically(destination: URL, with verified: VerifiedUpdate, requirement: String,
                                  verifyCopy: ((URL, VerifiedIdentity) -> Bool)? = nil) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(stagingPrefix(for: destination) + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        let copy = staging.appendingPathComponent(stagedCopyName(for: destination))
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            try fm.copyItem(at: verified.app, to: copy)
        } catch { throw OnePercentError.replaceFailed(error.localizedDescription) }
        let intact = verifyCopy?(copy, verified.identity) ?? isIntactCopy(at: copy, identity: verified.identity, requirement: requirement)
        guard intact else { throw OnePercentError.verificationFailed([.copyChanged]) }
        do { _ = try fm.replaceItemAt(destination, withItemAt: copy) } catch { throw OnePercentError.replaceFailed(error.localizedDescription) }
    }

    /// The copy is a real folder with the same bundle ID, version and build as at check time.
    static func copyMatchesIdentity(at app: URL, identity: VerifiedIdentity) -> Bool {
        guard let values = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              values.isSymbolicLink == false, values.isDirectory == true,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { return false }
        return info["CFBundleIdentifier"] as? String == identity.bundleID
            && info["CFBundleShortVersionString"] as? String == identity.version
            && info["CFBundleVersion"] as? String == identity.build
    }

    /// Identity plus a deep, strict signature check against the same requirement as the first check.
    static func isIntactCopy(at app: URL, identity: VerifiedIdentity, requirement: String) -> Bool {
        guard copyMatchesIdentity(at: app, identity: identity) else { return false }
        return ProcessRunner.run("/usr/bin/codesign", UpdateDecision.codesignArguments(appPath: app.path, requirement: requirement)).status == 0
    }

    /// Removes leftovers of an update that was interrupted (force quit, power loss): user-path staging copies next to
    /// the installed app, and this app's work folders in the temporary directory. Only items owned by this user.
    /// 2026-11-20 (Fable 리뷰): 하늘키보드는 강제 종료 때 응용 프로그램 폴더 옆에 숨은 사본(약 80MB)이 남았다.
    /// 2026-11-20 (보안 리뷰 P3-5): 10분 넘게 손대지 않은 것만 — 다른 인스턴스가 지금 하고 있는 업데이트를 지우지 않게.
    @discardableResult
    static func removeLeftovers(installedApp: URL, workPrefix: String, temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                                olderThan minimumAge: TimeInterval = 10 * 60, now: Date = Date()) -> Int {
        let fm = FileManager.default
        var removed = 0
        func sweep(_ folder: URL, prefix: String) {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
            // 2026-11-20 (리뷰): 접두어 뒤가 UUID 일 때만 — `com.x.app` 의 정리가 `com.x.app-helper` 의 진행 중 작업 폴더를 지우지 않게.
            for name in names where name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil {
                let url = folder.appendingPathComponent(name)
                // lstat: 링크는 건드리지 않고, 이 사용자 소유의 폴더·파일만 지운다(리서치 P3).
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
                      info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG,
                      now.timeIntervalSince1970 - Double(info.st_mtimespec.tv_sec) >= minimumAge else { continue }
                if (try? fm.removeItem(at: url)) != nil { removed += 1 }
            }
        }
        sweep(installedApp.deletingLastPathComponent(), prefix: stagingPrefix(for: installedApp))
        sweep(temporaryDirectory, prefix: workPrefix)
        return removed
    }
}

/// The administrator replacement for apps the user does not own (for example installed by `sudo`, or a standard account).
/// Runs as one shell command through `do shell script … with administrator privileges`.
///
/// 2026-11-07·11-13 (하늘키보드 #176·#226): 권한을 얻은 뒤 복사본을 다시 검증하고, root 만 이름을 바꿀 수 있는 자리
/// (끈적이 비트가 있는 /private/tmp 아래, root 소유 0700)에서 준비한다. 배치는 같은 볼륨의 이름 바꾸기 한 번이고,
/// 배치 뒤 파일 번호로 검증한 사본인지 확인한다. 백업은 복구할 수 있게 응용 프로그램 폴더에 두고, 성공 뒤 staging 안으로
/// 옮겨 파일 번호를 확인한 다음 지운다. setuid·setgid·그룹/다른 사용자 쓰기·ACL 을 벗기고 소유자를 옛 번들과 맞춘다.
/// ⚠️ 실제 관리자 계정에서의 동작은 실기 확인 항목이다(하늘키보드에서도 미검증 — #90·#226).
struct AdminReplacementScript {
    struct Commands {
        var copy = "/usr/bin/ditto"
        var move = "/bin/mv"
        var remove = "/bin/rm"
        var codesign = "/usr/bin/codesign"
        /// The uid that must own the installed app's folder. Always root in the product; tests (not root) use their own uid.
        var protectedOwner: UInt32 = 0
    }

    /// Exit codes the script uses. Anything else is a generic failure.
    enum Exit: Int32 {
        case copyChanged = 77
        case stagingUnsafe = 78
        case placeFailedRestored = 79
        case placeAndRestoreFailed = 80
        /// The item moved aside was not the one checked a moment before (a swap during the move).
        case backupMismatch = 81
        /// The installed app's folder is not protected, or the installed item is not this app.
        case destinationUnsafe = 82
    }

    let source: URL
    let destination: URL
    /// Owner-only staging folder; the app is copied to `stagedApp` inside it. Production uses ``privateStaging(bundleID:token:)``.
    let staging: URL
    let backup: URL
    let identity: VerifiedIdentity
    let requirement: String

    var stagedApp: URL { staging.appendingPathComponent(destination.lastPathComponent) }
    /// Where the backup is moved before deletion (inside staging).
    var retiredBackup: URL { staging.appendingPathComponent("previous.app") }

    static let privateParent = URL(fileURLWithPath: "/private/tmp")

    static func privateStaging(bundleID: String, token: String, parent: URL = privateParent) -> URL {
        parent.appendingPathComponent("OnePercent-\(bundleID)-\(token)")
    }

    func shellCommand(commands: Commands = Commands()) -> String {
        let copy = Self.shellQuote(commands.copy)
        let move = Self.shellQuote(commands.move)
        let remove = Self.shellQuote(commands.remove)
        let codesign = Self.shellQuote(commands.codesign)
        func ancestors(of start: URL) -> [String] {
            var list: [String] = []
            var url = start
            while url.path != "/" { list.append(url.path); url.deleteLastPathComponent() }
            return list
        }
        let linkChecks = ancestors(of: destination).map { "[ ! -L \(Self.shellQuote($0)) ] || reject" }.joined(separator: "\n")
        let stagingLinkChecks = ancestors(of: staging.deletingLastPathComponent())
            .map { "[ ! -L \(Self.shellQuote($0)) ] || refuse" }.joined(separator: "\n")
        return """
        source=\(Self.shellQuote(source.path))
        destination=\(Self.shellQuote(destination.path))
        parent=\(Self.shellQuote(destination.deletingLastPathComponent().path))
        staging=\(Self.shellQuote(staging.path))
        sparent=\(Self.shellQuote(staging.deletingLastPathComponent().path))
        staged=\(Self.shellQuote(stagedApp.path))
        retired=\(Self.shellQuote(retiredBackup.path))
        backup=\(Self.shellQuote(backup.path))
        info="$staged/Contents/Info.plist"
        created=0
        cleanup() {
            if [ "$created" = 1 ]; then \(remove) -rf "$staging"; fi
        }
        reject() {
            cleanup
            printf '%s\\n' 'onepercent: copy-changed' >&2
            exit \(Exit.copyChanged.rawValue)
        }
        refuse() {
            cleanup
            printf '%s\\n' 'onepercent: staging-unsafe' >&2
            exit \(Exit.stagingUnsafe.rawValue)
        }
        unsafe() {
            cleanup
            printf '%s\\n' 'onepercent: destination-unsafe' >&2
            exit \(Exit.destinationUnsafe.rawValue)
        }
        \(linkChecks)
        \(stagingLinkChecks)
        # 2026-11-20 (PR #1 보안 리뷰 P1-1): 설치 위치의 부모가 root 소유이고 다른 사용자가 쓸 수 없을 때만 root 로 손댄다.
        # (그룹 쓰기는 /Applications 의 기본값 root:admin 775 라 허용 — 그 대신 아래 mv -h·파일 번호·옛 앱 신원 확인으로 막는다.)
        pinfo="$(/usr/bin/stat -f '%u:%Lp' "$parent")" || unsafe
        [ "${pinfo%%:*}" = \(commands.protectedOwner) ] || unsafe
        [ "$(( 0${pinfo##*:} & 002 ))" -eq 0 ] || unsafe
        # 지금 그 자리에 있는 것이 이 앱인가 — 남의 폴더를 이 앱으로 알고 옮기거나 지우지 않게.
        [ -d "$destination" ] && [ ! -L "$destination" ] || unsafe
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" = \(Self.shellQuote(identity.bundleID)) ] || unsafe
        # staging 의 부모는 root(또는 이 실행 계정) 소유이고, 끈적이 비트가 있거나 그룹·다른 사용자가 쓸 수 없어야 한다.
        [ -d "$sparent" ] || refuse
        sowner="$(/usr/bin/stat -f %u "$sparent")" || refuse
        [ "$sowner" = 0 ] || [ "$sowner" = "$(/usr/bin/id -u)" ] || refuse
        smode="$(/usr/bin/stat -f %Lp "$sparent")" || refuse
        [ -k "$sparent" ] || [ "$(( 0$smode & 022 ))" -eq 0 ] || refuse
        if ! /bin/mkdir -m 700 "$staging"; then
            exit 1
        fi
        created=1
        [ -d "$staging" ] && [ ! -L "$staging" ] || refuse
        [ "$(/usr/bin/stat -f '%u:%Lp' "$staging")" = "$(/usr/bin/id -u):700" ] || refuse
        # 마지막 배치가 이름 바꾸기 한 번이어야 원자적이다. 다른 볼륨이면 mv 가 복사로 바뀌므로 거부한다.
        [ "$(/usr/bin/stat -f %d "$staging")" = "$(/usr/bin/stat -f %d "$parent")" ] || refuse
        if ! \(copy) "$source" "$staged"; then
            cleanup
            exit 1
        fi
        [ -d "$staged" ] && [ ! -L "$staged" ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" = \(Self.shellQuote(identity.bundleID)) ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" = \(Self.shellQuote(identity.version)) ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" = \(Self.shellQuote(identity.build)) ] || reject
        \(codesign) --verify --deep --strict --all-architectures \(Self.shellQuote("-R=" + requirement)) "$staged" || reject
        # 2026-11-20 (보안 리뷰 P1-1): 소유자를 바꿔치기할 수 있는 옛 번들에서 읽지 않는다 — 이 스크립트를 실행하는 계정(관리자 경로에선 root:wheel).
        owner="$(/usr/bin/id -u):$(/usr/bin/id -g)" || reject
        /bin/chmod -R u-s,g-s,go-w "$staged" || reject
        /bin/chmod -RN "$staged" || reject
        /usr/sbin/chown -hR "$owner" "$staged" || reject
        previous_id="$(/usr/bin/stat -f '%i:%d' "$destination")" || reject
        staged_id="$(/usr/bin/stat -f '%i:%d' "$staged")" || reject
        # mv -h: 대상이 폴더를 가리키는 링크여도 따라 들어가지 않고 그 이름으로 바꾼다(보안 리뷰 P1-1, 이 macOS 에서 실측).
        if ! \(move) -h "$destination" "$backup"; then
            cleanup
            exit 1
        fi
        # 옮긴 것이 방금 확인한 그 항목인지 — 아니면 더 손대지 않고 멈춘다.
        if [ -L "$backup" ] || [ "$(/usr/bin/stat -f '%i:%d' "$backup")" != "$previous_id" ]; then
            printf '%s\\n' 'onepercent: backup-mismatch' >&2
            exit \(Exit.backupMismatch.rawValue)
        fi
        # 실행 경로가 비어 있을 때만 놓고, 놓은 뒤 그 자리가 검증한 사본인지 파일 번호로 확인한다.
        if [ ! -e "$destination" ] && [ ! -L "$destination" ] && \(move) -h "$staged" "$destination" \\
            && [ ! -L "$destination" ] && [ "$(/usr/bin/stat -f '%i:%d' "$destination")" = "$staged_id" ]; then
            # 새 앱 배치가 끝났으므로 백업 정리 실패는 교체 실패로 치지 않는다.
            # 지우기 전에 옛 앱인지 확인한다: 파일 번호, 번들 ID, 같은 요구사항의 서명(보안 리뷰 P1-1 고침 5). 아니면 지우지 않고 남긴다.
            if \(move) -h "$backup" "$retired" && [ ! -L "$retired" ] \\
                && [ "$(/usr/bin/stat -f '%i:%d' "$retired")" = "$previous_id" ] \\
                && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$retired/Contents/Info.plist")" = \(Self.shellQuote(identity.bundleID)) ] \\
                && \(codesign) --verify --deep --strict --all-architectures \(Self.shellQuote("-R=" + requirement)) "$retired"; then
                if ! \(remove) -rf "$staging"; then
                    printf '%s\\n' "onepercent: backup-cleanup-failed $staging"
                fi
            else
                # 백업 자리에 다른 항목이 있었다. 지우지 않고 제자리로 돌려놓는다.
                if { [ -e "$retired" ] || [ -L "$retired" ]; } && [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
                    \(move) -h "$retired" "$backup"
                fi
                if [ ! -e "$retired" ] && [ ! -L "$retired" ]; then
                    \(remove) -rf "$staging"
                fi
                printf '%s\\n' "onepercent: backup-cleanup-failed $backup"
            fi
        else
            # 다른 항목이 실행 경로에 생겼다면 덮어쓰거나 그 안에 백업을 넣지 않는다.
            if [ ! -e "$destination" ] && [ ! -L "$destination" ] && \(move) -h "$backup" "$destination"; then
                cleanup
                printf '%s\\n' 'onepercent: place-failed-restored' >&2
                exit \(Exit.placeFailedRestored.rawValue)
            fi
            # 복구도 실패하면 백업과 staging 을 모두 남겨 손으로 되돌리는 데 쓴다.
            printf '%s\\n' 'onepercent: place-and-restore-failed' >&2
            exit \(Exit.placeAndRestoreFailed.rawValue)
        fi
        """
    }

    var appleScriptSource: String {
        "do shell script \(Self.appleScriptLiteral(shellCommand())) with administrator privileges"
    }

    /// Maps the script's exit status and message to an error.
    func error(status: Int, message: String) -> OnePercentError {
        switch Exit(rawValue: Int32(clamping: status)) {
        case .copyChanged: .copyChanged
        case .stagingUnsafe: .stagingUnsafe
        case .placeFailedRestored: .placeFailedRestored
        case .placeAndRestoreFailed, .backupMismatch:
            .replaceRecoveryFailed(reason: message, backupPath: backup.path, destinationPath: destination.path)
        case .destinationUnsafe: .replaceFailed("the app's folder is not protected, or the installed item is not this app")
        case nil: .replaceFailed(message)
        }
    }

    /// POSIX single quotes.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// An AppleScript string literal.
    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
