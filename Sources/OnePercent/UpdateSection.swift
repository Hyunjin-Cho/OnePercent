import SwiftUI

/// A ready-made update section for your settings, in your app's language and the system's own look:
/// where things stand, the button for the next step (Check Now, Install New Version or Cancel), download progress,
/// the What's New link, and the switch for background checks.
///
/// ```swift
/// Form {
///     Section { OnePercentUpdateSection(updater: updater) }
/// }
/// ```
///
/// For a different look, build your own from ``OnePercentUpdater/presentation`` and ``OnePercentText`` — this view uses
/// nothing else.
///
/// 2026-11-24 (#37): 붙이는 앱마다 같은 화면(상태 한 줄·작은 줄·다음 단계 버튼·진행률·스위치)을 새로 짰다(PomoLight·시험 앱).
/// 그 규칙을 한 곳에 모았다. 문장을 고르는 부분은 ``UpdateSectionContent`` 로 떼어 SwiftUI 없이 시험한다.
public struct OnePercentUpdateSection: View {
    private let updater: OnePercentUpdater
    private let showsAutomaticChecksSwitch: Bool

    /// - Parameters:
    ///   - updater: Your app's one updater.
    ///   - showsAutomaticChecksSwitch: Show the switch for background checks. Default: `true`.
    public init(updater: OnePercentUpdater, showsAutomaticChecksSwitch: Bool = true) {
        self.updater = updater
        self.showsAutomaticChecksSwitch = showsAutomaticChecksSwitch
    }

    public var body: some View {
        let presentation = updater.presentation
        let content = UpdateSectionContent(updater: updater)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: content.headline)
                    HStack(spacing: 6) {
                        Text(verbatim: content.detail)
                        if let page = content.releasePage {
                            Link(destination: page) { Text(verbatim: OnePercentText.releaseNotes) }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if case .downloading(let fraction) = presentation.line {
                        if let fraction {
                            ProgressView(value: fraction).progressViewStyle(.linear)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                    }
                    if let error = presentation.errorText {
                        Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
                button(presentation)
            }
            if showsAutomaticChecksSwitch {
                Toggle(isOn: Binding(get: { updater.automaticChecksEnabled }, set: { updater.setAutomaticChecksEnabled($0) })) {
                    Text(verbatim: OnePercentText.automaticChecks)
                }
            }
        }
    }

    @ViewBuilder
    private func button(_ presentation: UpdateStatusPresentation) -> some View {
        if presentation.showsCancelButton {
            Button { updater.cancel() } label: { Text(verbatim: OnePercentText.cancel) }
        } else if presentation.showsInstallButton {
            Button { Task { await updater.installAvailableUpdate() } } label: { Text(verbatim: OnePercentText.install) }
                .buttonStyle(.borderedProminent)
        } else {
            // The result shows right here, so the found version also counts as announced (no popup repeats it later).
            Button { Task { await updater.checkNow(userInitiated: true, showNotice: false) } } label: { Text(verbatim: OnePercentText.checkNow) }
                .disabled(presentation.line != .none)
        }
    }
}

/// The words ``OnePercentUpdateSection`` shows, chosen from the updater's state.
@MainActor
struct UpdateSectionContent: Equatable {
    /// Where things stand: the progress line, "Updated to …", "You're up to date." or the installed version.
    let headline: String
    /// Under it: both versions while a new one is offered ("Installed version 1.0 · Latest version 1.1"), otherwise when
    /// GitHub was last asked.
    let detail: String
    /// The release notes of the offered version, or of the version just updated to.
    let releasePage: URL?

    init(updater: OnePercentUpdater) {
        let presentation = updater.presentation
        let installed = OnePercentText.installedVersion + " " + updater.currentVersion
        if let line = presentation.text {
            headline = line
        } else if let updated = updater.justUpdatedTo {
            headline = OnePercentText.updated(to: updated)
        } else if updater.phase == .upToDate, !Self.isIncompatibility(updater.lastError) {
            headline = OnePercentText.upToDate
        } else {
            // A newer version exists that this Mac cannot open (#33): not "up to date" — the error line says why.
            headline = installed
        }
        if presentation.line == .newVersion, let latest = updater.latestVersion {
            detail = installed + " · " + OnePercentText.latestVersion + " " + latest
        } else {
            detail = updater.lastCheck.map(OnePercentText.lastChecked) ?? OnePercentText.neverChecked
        }
        if case .available(let update) = updater.phase {
            releasePage = update.pageURL
        } else if presentation.line == .none, let updated = updater.justUpdatedTo {
            releasePage = updater.releasePageURL(forVersion: updated)
        } else {
            releasePage = nil
        }
    }

    private static func isIncompatibility(_ error: OnePercentError?) -> Bool {
        switch error {
        case .requiresNewerSystem, .unsupportedProcessor: true
        default: false
        }
    }
}
