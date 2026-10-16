import AVFoundation
import Darwin
import Foundation
import Pipeline

/// Orchestrates the record → transcribe → substitute → inject loop.
/// Called by AppDelegate on hotkey press/release.
public final class AppCoordinator: @unchecked Sendable {

    public enum CoordinatorError: Error, LocalizedError, Equatable {
        case apiKeyNotSet
        case micAccessDenied
        case emptyRecording
        case silenceDetected

        public var errorDescription: String? {
            switch self {
            case .apiKeyNotSet: return "API key not set — open Dashboard → Settings"
            case .micAccessDenied: return "Mic access denied"
            case .emptyRecording: return nil
            case .silenceDetected: return nil
            }
        }
    }

    private let audioRecorder = AudioRecorder()
    private let profileStore = ProfileStore()
    private let injector = Injector()
    private let history = TranscriptionHistory()
    private var correctionController: CorrectionController?

    /// Expose audio spectrum bands for UI visualization
    var onSpectrum: (([Float]) -> Void)? {
        get { audioRecorder.onSpectrum }
        set { audioRecorder.onSpectrum = newValue }
    }

    /// Called when the 60s recording limit is hit (auto-stop).
    var onAutoStop: (() -> Void)?
    /// Called once when recording approaches the 60s limit (~50s).
    var onNearLimit: (() -> Void)?

    public init() {
        let controller = CorrectionController(profileStore: profileStore, injector: injector)
        self.correctionController = controller
    }

    /// Start recording audio. Throws if the mic can't be opened.
    public func startRecording() throws {
        audioRecorder.onAutoStop = { [weak self] in
            self?.onAutoStop?()
        }
        audioRecorder.onNearLimit = { [weak self] in
            self?.onNearLimit?()
        }
        try audioRecorder.startRecording()
    }

    /// Stop recording and throw the audio away. Nothing is sent or typed.
    public func cancelRecording() {
        _ = audioRecorder.stopRecording()
    }

    /// Stop recording and process the audio.
    /// - Parameters:
    ///   - onWillTranscribe: Called after pre-flight checks pass, just before the API call.
    ///   - completion: Final result callback.
    public func stopRecording(onWillTranscribe: (() -> Void)? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let audioData = audioRecorder.stopRecording()

        guard !audioData.isEmpty else {
            completion(.failure(CoordinatorError.emptyRecording))
            return
        }

        // Minimum duration gate: skip accidental taps (< 300ms)
        let durationSeconds = Double(audioData.count) / Double(16000 * MemoryLayout<Float>.size)
        guard durationSeconds >= 0.3 else {
            completion(.failure(CoordinatorError.emptyRecording))
            return
        }

        // RMS energy gate: skip silence (no speech detected)
        let floatCount = audioData.count / MemoryLayout<Float>.size
        var sumOfSquares: Float = 0
        audioData.withUnsafeBytes { ptr in
            let floats = ptr.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                sumOfSquares += floats[i] * floats[i]
            }
        }
        let rms = sqrtf(sumOfSquares / Float(floatCount))
        guard rms >= 0.005 else {
            completion(.failure(CoordinatorError.silenceDetected))
            return
        }

        guard let apiKey = try? profileStore.getApiKey(), !apiKey.isEmpty else {
            completion(.failure(CoordinatorError.apiKeyNotSet))
            return
        }

        onWillTranscribe?()

        let transcriber = Transcriber(apiKey: apiKey)

        Task {
            do {
                let result = try await transcriber.transcribe(audioData: audioData)
                let rawText = result.text

                // ── Interception seam (SPEC §7) ───────────────────────────────
                // If the correction/command window is open, the next utterance
                // is first tested as an editing command, then as a voice
                // correction. If handled, execute it and return early — do NOT
                // inject it as normal text.
                if let controller = correctionController, controller.isWindowOpen {
                    if let command = CommandGrammar.parse(rawText) {
                        if let status = controller.processCommand(command) {
                            history.append(raw: rawText, corrected: status, latencyMs: result.latencyMs, injectionMethod: "command")
                            completion(.success(status))
                            return
                        }
                    }
                    if let correction = controller.processUtterance(rawText), correction.learned {
                        let status = "learned: \(correction.heard) → \(correction.intended)"
                        history.append(raw: rawText, corrected: status, latencyMs: result.latencyMs, injectionMethod: "correction")
                        completion(.success(status))
                        return
                    }
                    // No command/correction matched — fall through to normal path.
                    // (processUtterance already closed the window on a non-match.)
                }

                // ── Normal path ───────────────────────────────────────────────
                // rawText → DisfluencyFilter (if enabled) → Substitutor(vocab)
                //         → SnippetExpander(snippets) → inject → history.
                let profile = try? profileStore.read()
                let vocab = profile?.vocab ?? [:]
                let snippets = profile?.snippets ?? [:]
                let removeFillers = profile?.removeFillers ?? false

                let cleaned = removeFillers ? DisfluencyFilter.apply(rawText) : rawText
                let substituted = Substitutor.apply(cleaned, vocab: vocab)
                let correctedText = SnippetExpander.apply(substituted, snippets: snippets)

                let injectionResult = injector.inject(correctedText)
                let method: String
                switch injectionResult {
                case .inserted: method = "inserted"
                case .copiedToClipboard: method = "clipboard"
                case .failure(let r): method = "failed:\(r)"
                }

                history.append(raw: rawText, corrected: correctedText, latencyMs: result.latencyMs, injectionMethod: method)

                switch injectionResult {
                case .inserted:
                    // Only open the window when text actually landed — otherwise
                    // "scratch that" would backspace text we never typed.
                    correctionController?.openWindow(afterInjecting: correctedText)
                    completion(.success(correctedText))
                case .copiedToClipboard:
                    completion(.success("Copied to clipboard. Press ⌘V to paste."))
                case .failure(let reason):
                    completion(.failure(NSError(domain: "bak-bak", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
