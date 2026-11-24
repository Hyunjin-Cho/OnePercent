import Foundation

/// What an update UI should show right now. Settings rows and menu items can share it.
///
/// 2026-11-20: 하늘키보드 `UpdateStatusPresentation`(#227)을 옮기며, 실패가 "새 버전 있음"을 덮어쓰던 문제를 고쳤다(Fable 리뷰) —
/// 이제 오류는 상태와 따로 오고, 새 버전이 있는 동안에는 오류가 나도 설치 버튼이 남는다.
public struct UpdateStatusPresentation: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        case none, checking, newVersion, downloading(fraction: Double?), verifying, installing
    }

    public let line: Line
    /// Show the install button.
    public let showsInstallButton: Bool
    /// Pressing install must ask GitHub again first (after a relaunch only the stored latest version is known, not the file).
    public let installRechecksFirst: Bool
    /// Show a cancel button (while downloading or verifying).
    public let showsCancelButton: Bool
    /// Show a "new version" item in a menu.
    public let showsMenuNotice: Bool
    /// The last error, if any — shown in addition to the line.
    public let error: OnePercentError?

    static func resolve(phase: OnePercentUpdater.Phase, error: OnePercentError?, storedLatestIsNewer: Bool) -> Self {
        switch phase {
        case .available:
            return Self(resolved: .newVersion, install: true, menu: true, error: error)
        case .idle where storedLatestIsNewer:
            // 2026-11-13 (하늘키보드 #227 F-2): 다시 켠 뒤에도 설치 버튼이 남아야 한다. 버튼은 누를 때 다시 물은 뒤 설치한다.
            return Self(resolved: .newVersion, install: true, recheck: true, menu: true, error: error)
        case .idle, .upToDate:
            return Self(resolved: .none, error: error)
        case .checking:
            return Self(resolved: .checking)
        case .downloading(let fraction):
            return Self(resolved: .downloading(fraction: fraction), cancel: true)
        case .verifying:
            return Self(resolved: .verifying, cancel: true)
        case .installing:
            return Self(resolved: .installing)
        }
    }

    /// For previews and tests of your own UI. Real values come from ``OnePercentUpdater/presentation``.
    public init(line: Line, showsInstallButton: Bool = false, installRechecksFirst: Bool = false, showsCancelButton: Bool = false,
                showsMenuNotice: Bool = false, error: OnePercentError? = nil) {
        self.init(resolved: line, install: showsInstallButton, recheck: installRechecksFirst, cancel: showsCancelButton,
                  menu: showsMenuNotice, error: error)
    }

    private init(resolved line: Line, install: Bool = false, recheck: Bool = false, cancel: Bool = false, menu: Bool = false,
                 error: OnePercentError? = nil) {
        self.line = line
        self.showsInstallButton = install
        self.installRechecksFirst = recheck
        self.showsCancelButton = cancel
        self.showsMenuNotice = menu
        self.error = error
    }

    /// The line as localized text, or `nil` for `.none`.
    public var text: String? {
        switch line {
        case .none: nil
        case .checking: OnePercentText.checking
        case .newVersion: OnePercentText.available
        case .downloading(let fraction): OnePercentText.downloading(fraction)
        case .verifying: OnePercentText.verifying
        case .installing: OnePercentText.installing
        }
    }

    /// The error as localized text ("Update error: … (code)", see ``OnePercentText/error(_:)``), or `nil`.
    /// A user's own cancel is shown without the "error" prefix and without a code.
    public var errorText: String? {
        guard let error else { return nil }
        return error == .cancelled ? error.localizedDescription : OnePercentText.error(error)
    }
}
