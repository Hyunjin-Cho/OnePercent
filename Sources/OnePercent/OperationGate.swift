import Foundation
import Observation

/// One big operation at a time. Share one gate between OnePercent and your app's own long operations
/// (for example "reset everything" or an uninstaller) so they never run together.
///
/// 2026-11-20: 하늘키보드 `ProductOperationGate`(설치·활성화·업데이트·제거가 같은 작업권을 나눠 씀)를 이름만 받는 일반형으로 옮겼다.
@MainActor
@Observable
public final class OperationGate {
    /// The running operation's name, or `nil`.
    public private(set) var operation: String?
    @ObservationIgnored private var token: UUID?

    public init() {}

    /// Starts `name` and returns a token, or `nil` when something else is running.
    public func begin(_ name: String) -> UUID? {
        guard operation == nil else { return nil }
        let id = UUID()
        token = id
        operation = name
        return id
    }

    /// Ends the operation started with `token`. Other tokens are ignored.
    public func finish(_ id: UUID) {
        guard token == id else { return }
        token = nil
        operation = nil
    }
}
