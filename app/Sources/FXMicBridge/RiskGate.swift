import FXMicCore
import Foundation

/// Asks the user on the mic before a risky agent action (TDD voice command agent §3.5): the island
/// says what would happen, the red LEDs blink, grey = yes, a short shake = no, silence = no.
@MainActor
final class RiskGate {
    var onAsk: ((PendingAction) -> Void)?
    var onEnd: ((Bool) -> Void)?
    private var pending: CheckedContinuation<Bool, Never>?
    private var timer: Timer?

    var isWaiting: Bool { pending != nil }

    func ask(_ action: PendingAction, timeoutMs: Double) async -> Bool {
        resolve(false)   // a question still open from before is answered no
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = continuation
                onAsk?(action)
                timer = Timer.scheduledTimer(withTimeInterval: timeoutMs / 1000, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resolve(false) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(false) }
        }
    }

    func resolve(_ yes: Bool) {
        timer?.invalidate()
        timer = nil
        guard let continuation = pending else { return }
        pending = nil
        onEnd?(yes)
        continuation.resume(returning: yes)
    }
}
