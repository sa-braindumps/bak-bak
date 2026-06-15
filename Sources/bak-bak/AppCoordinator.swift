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

    /// Start recording audio.
    public func startRecording() {
        audioRecorder.onAutoStop = { [weak self] in
            self?.onAutoStop?()
        }
        audioRecorder.onNearLimit = { [weak self] in
            self?.onNearLimit?()
        }
        do {
            try audioRecorder.startRecording()
        } catch {
            // Error will be surfaced via callback
        }
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
                let profile = try? profileStore.read()
                let vocab = profile?.vocab ?? [:]
                let correctedText = Substitutor.apply(result.text, vocab: vocab)

                let injectionResult = injector.inject(correctedText)
                let method: String
                switch injectionResult {
                case .inserted: method = "inserted"
                case .failure(let r): method = "failed:\(r)"
                }

                history.append(raw: result.text, corrected: correctedText, latencyMs: result.latencyMs, injectionMethod: method)

                switch injectionResult {
                case .inserted:
                    completion(.success(correctedText))
                case .failure(let reason):
                    completion(.failure(NSError(domain: "bak-bak", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])))
                }

                correctionController?.openWindow(afterInjectionLength: correctedText.count)
            } catch {
                completion(.failure(error))
            }
        }
    }
}
