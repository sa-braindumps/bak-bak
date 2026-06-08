import AVFoundation
import Foundation
import Pipeline

/// Orchestrates the record → transcribe → substitute → inject loop.
/// Called by AppDelegate on hotkey press/release.
public final class AppCoordinator: @unchecked Sendable {

    public enum CoordinatorError: Error, LocalizedError {
        case apiKeyNotSet
        case micAccessDenied
        case emptyRecording

        public var errorDescription: String? {
            switch self {
            case .apiKeyNotSet: return "API key not set — run bak-bak setup"
            case .micAccessDenied: return "Mic access denied"
            case .emptyRecording: return nil
            }
        }
    }

    private let audioRecorder = AudioRecorder()
    private let profileStore = ProfileStore()
    private let injector = Injector()
    private let history = TranscriptionHistory()
    private var correctionController: CorrectionController?

    public init() {
        let controller = CorrectionController(profileStore: profileStore, injector: injector)
        self.correctionController = controller
    }

    /// Start recording audio.
    public func startRecording() {
        do {
            try audioRecorder.startRecording()
        } catch {
            // Error will be surfaced via callback
        }
    }

    /// Stop recording and process the audio.
    public func stopRecording(completion: @escaping (Result<String, Error>) -> Void) {
        let audioData = audioRecorder.stopRecording()

        guard !audioData.isEmpty else {
            completion(.failure(CoordinatorError.emptyRecording))
            return
        }

        guard let apiKey = try? profileStore.getApiKey(), !apiKey.isEmpty else {
            completion(.failure(CoordinatorError.apiKeyNotSet))
            return
        }

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

                // Open correction window
                correctionController?.openWindow(afterInjectionLength: correctedText.count)
            } catch {
                completion(.failure(error))
            }
        }
    }
}
