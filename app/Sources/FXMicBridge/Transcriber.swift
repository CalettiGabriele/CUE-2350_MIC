import FXMicCore
import Foundation
import WhisperKit
import os

/// Local speech-to-text with WhisperKit (TDD §3.7).
actor Transcriber {
    enum State: Equatable {
        case notLoaded
        case loading
        case ready(model: String)
        case failed(String)
    }

    private let log = Logger(subsystem: "com.fxmicbridge", category: "stt")
    private var kit: WhisperKit?
    private(set) var state: State = .notLoaded

    /// Downloads (first run) and loads the Core ML model into `folder`.
    func load(model: String, folder: URL) async {
        state = .loading
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let config = WhisperKitConfig(model: model, downloadBase: folder, verbose: false,
                                          logLevel: .error, prewarm: true, load: true, download: true)
            kit = try await WhisperKit(config)
            state = .ready(model: model)
            log.info("model ready: \(model, privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("model load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `language` nil = auto-detect. `vocabulary` is passed as Whisper prompt tokens.
    func transcribe(_ audio: [Float], language: String?, vocabulary: [String]) async throws -> String {
        guard let kit else { throw NSError(domain: "Transcriber", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: L.t("Model not loaded")]) }
        var promptTokens: [Int]?
        if !vocabulary.isEmpty, let tokenizer = kit.tokenizer {
            promptTokens = tokenizer.encode(text: " " + vocabulary.joined(separator: ", "))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            noSpeechThreshold: 0.6
        )
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
