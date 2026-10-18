import Foundation

/// Dictation state machine (TDD §3.5). M1 runs Raw only, so `postProcessing` is skipped
/// when `usesLLM` is false.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording(startedAt: Double)
    case transcribing
    case postProcessing
    case injecting
}

public enum DictationInput: Equatable, Sendable {
    case pttDown(at: Double)
    case pttUp(at: Double)
    case cancel
    case transcribed(text: String, usesLLM: Bool)
    case postProcessed
    case injected
    case failed
}

public enum DictationEffect: Equatable, Sendable {
    case startRecording
    case stopRecordingAndTranscribe
    case discardRecording(reason: String)
    case runPostProcessing
    case inject
    case busy
    case none
}

public struct DictationStateMachine {
    public private(set) var state: DictationState = .idle
    public var minDurationMs: Double

    public init(minDurationMs: Double = 300) {
        self.minDurationMs = minDurationMs
    }

    public mutating func send(_ input: DictationInput) -> DictationEffect {
        switch (state, input) {
        case (.idle, .pttDown(let t)):
            state = .recording(startedAt: t)
            return .startRecording
        case (_, .pttDown):
            return .busy
        case (.recording(let start), .pttUp(let t)):
            if t - start < minDurationMs {
                state = .idle
                return .discardRecording(reason: "too short")
            }
            state = .transcribing
            return .stopRecordingAndTranscribe
        case (.recording, .cancel):
            state = .idle
            return .discardRecording(reason: "cancelled")
        case (.transcribing, .cancel), (.postProcessing, .cancel):
            state = .idle
            return .discardRecording(reason: "cancelled")
        case (.transcribing, .transcribed(let text, let usesLLM)):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state = .idle
                return .discardRecording(reason: "no speech")
            }
            state = usesLLM ? .postProcessing : .injecting
            return usesLLM ? .runPostProcessing : .inject
        case (.postProcessing, .postProcessed):
            state = .injecting
            return .inject
        case (.injecting, .injected), (_, .failed):
            state = .idle
            return .none
        default:
            return .none
        }
    }
}
