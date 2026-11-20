import Foundation

/// Why a check or an install did not happen. ``code`` is stable for logs and tests; the description is localized.
///
/// 2026-11-20: 하늘키보드는 한국어 문장을 오류 값에 바로 넣었다. 여기서는 값(코드)과 문장(29개 언어)을 나눴다.
public enum OnePercentError: Error, Equatable, Sendable {
    case badConfiguration(String)
    case network(String)
    case httpStatus(Int)
    case rateLimited
    case noRelease(String)
    case redirectBlocked(String)
    case malformedResponse
    case responseTooLarge(Int)
    /// A newer tag exists but its ZIP is not attached (yet).
    case assetNotReady(String)
    case badSize(Int)
    case sizeMismatch(expected: Int, actual: Int)
    /// The file's SHA-256 is not the one GitHub published for the asset.
    case digestMismatch
    case extractFailed(String)
    case archiveRejected(ArchiveProblem)
    case verificationFailed([VerificationFailure])
    case notAtRequiredLocation(required: String, running: String)
    case translocated
    case readOnlyVolume
    /// Another update, or an operation the app registered on the shared ``OperationGate``, is running.
    case busy
    /// The app's ``OnePercentUpdater/installGuard`` refused, with the app's own (already localized) reason.
    case blocked(String)
    case cancelled
    case replaceFailed(String)
    case stagingUnsafe
    case copyChanged
    case placeFailedRestored
    case replaceRecoveryFailed(reason: String, backupPath: String, destinationPath: String)
    case relaunchFailed(String)

    /// A stable identifier, for logs and tests.
    public var code: String {
        switch self {
        case .badConfiguration: "badConfiguration"
        case .network: "network"
        case .httpStatus: "httpStatus"
        case .rateLimited: "rateLimited"
        case .noRelease: "noRelease"
        case .redirectBlocked: "redirectBlocked"
        case .malformedResponse: "malformedResponse"
        case .responseTooLarge: "responseTooLarge"
        case .assetNotReady: "assetNotReady"
        case .badSize: "badSize"
        case .sizeMismatch: "sizeMismatch"
        case .digestMismatch: "digestMismatch"
        case .extractFailed: "extractFailed"
        case .archiveRejected: "archiveRejected"
        case .verificationFailed: "verificationFailed"
        case .notAtRequiredLocation: "notAtRequiredLocation"
        case .translocated: "translocated"
        case .readOnlyVolume: "readOnlyVolume"
        case .busy: "busy"
        case .blocked: "blocked"
        case .cancelled: "cancelled"
        case .replaceFailed: "replaceFailed"
        case .stagingUnsafe: "stagingUnsafe"
        case .copyChanged: "copyChanged"
        case .placeFailedRestored: "placeFailedRestored"
        case .replaceRecoveryFailed: "replaceRecoveryFailed"
        case .relaunchFailed: "relaunchFailed"
        }
    }
}

extension OnePercentError: LocalizedError {
    public var errorDescription: String? { message(L10n.current) }

    func message(_ t: L10n.Table) -> String {
        switch self {
        case .badConfiguration(let reason): t.text("error.badConfiguration", reason)
        case .network(let reason): t.text("error.network", reason)
        case .httpStatus(let code): t.text("error.httpStatus", String(code))
        case .rateLimited: t.text("error.rateLimited")
        case .noRelease(let repository): t.text("error.noRelease", repository)
        case .redirectBlocked(let target): t.text("error.redirectBlocked", target)
        case .malformedResponse: t.text("error.malformedResponse")
        case .responseTooLarge(let limit): t.text("error.responseTooLarge", t.bytes(limit))
        case .assetNotReady(let version): t.text("error.assetNotReady", version)
        case .badSize(let size): t.text("error.badSize", t.bytes(size))
        case .sizeMismatch(let expected, let actual): t.text("error.sizeMismatch", t.bytes(expected), t.bytes(actual))
        case .digestMismatch: t.text("error.digestMismatch")
        case .extractFailed(let reason): t.text("error.extractFailed", reason)
        case .archiveRejected(let problem): t.text("error.archiveRejected", problem.message(t))
        case .verificationFailed(let failures):
            t.text("error.verificationFailed", failures.map { $0.message(t) }.joined(separator: t.text("list.separator")))
        case .notAtRequiredLocation(let required, let running): t.text("error.notAtRequiredLocation", required, running)
        case .translocated: t.text("error.translocated")
        case .readOnlyVolume: t.text("error.readOnlyVolume")
        case .busy: t.text("error.busy")
        case .blocked(let reason): reason
        case .cancelled: t.text("error.cancelled")
        case .replaceFailed(let reason): t.text("error.replaceFailed", reason)
        case .stagingUnsafe: t.text("error.stagingUnsafe")
        case .copyChanged: t.text("error.copyChanged")
        case .placeFailedRestored: t.text("error.placeFailedRestored")
        case .replaceRecoveryFailed(let reason, let backup, let destination):
            t.text("error.replaceRecoveryFailed", backup, destination, reason)
        case .relaunchFailed(let reason): t.text("error.relaunchFailed", reason)
        }
    }
}

/// One failed check on the downloaded app.
public enum VerificationFailure: Equatable, Sendable {
    case bundleIdentifierMismatch
    case notSignedByTeam
    case codeSignatureInvalid
    case notarizationRejected
    case versionNotHigher
    case releaseMismatch(bundleVersion: String?, releaseVersion: String)
    case versionUnreadable
    case notARealFolder
    case copyChanged

    func message(_ t: L10n.Table) -> String {
        switch self {
        case .bundleIdentifierMismatch: t.text("verify.bundleIdentifier")
        case .notSignedByTeam: t.text("verify.team")
        case .codeSignatureInvalid: t.text("verify.codesign")
        case .notarizationRejected: t.text("verify.notarization")
        case .versionNotHigher: t.text("verify.notHigher")
        case .releaseMismatch(let bundle, let release): t.text("verify.releaseMismatch", bundle ?? t.text("verify.unknownValue"), release)
        case .versionUnreadable: t.text("verify.unreadable")
        case .notARealFolder: t.text("verify.notFolder")
        case .copyChanged: t.text("verify.copyChanged")
        }
    }
}

extension ArchiveProblem {
    func message(_ t: L10n.Table) -> String {
        switch self {
        case .unreadableListing: t.text("archive.unreadable")
        case .empty: t.text("archive.empty")
        case .tooManyEntries(let count, let max): t.text("archive.tooManyEntries", String(count), String(max))
        case .tooLarge(let mb): t.text("archive.tooLarge", String(mb))
        case .outsideApp(let app): t.text("archive.outsideApp", app)
        case .linkedEntry(let app): t.text("archive.linkedEntry", app)
        case .unexpectedTopLevel(let app, let count): t.text("archive.unexpectedTopLevel", app, String(count))
        case .extractedTooLarge(let mb): t.text("archive.extractedTooLarge", String(mb))
        case .extractedTooManyItems(let max): t.text("archive.extractedTooManyItems", String(max))
        case .extractionTimedOut(let seconds): t.text("archive.timedOut", String(seconds))
        case .escapingLink(let app): t.text("archive.escapingLink", app)
        case .missingApp(let app): t.text("archive.missingApp", app)
        }
    }
}
