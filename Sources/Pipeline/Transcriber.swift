import Foundation

/// Sends audio data to the OpenAI transcription API via a single multipart POST.
/// No SDK — raw URLSession. Measures round-trip latency for `doctor`.
public final class Transcriber: @unchecked Sendable {

    public enum TranscriptionError: Error, LocalizedError {
        case noNetwork
        case apiKeyRejected
        case rateLimited
        case serverError
        case timeout
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .noNetwork: return "no network"
            case .apiKeyRejected: return "API key rejected"
            case .rateLimited: return "rate limited or out of quota"
            case .serverError: return "Whisper API error (5xx)"
            case .timeout: return "transcription timed out"
            case .emptyResponse: return nil
            }
        }
    }

    public struct TranscriptionResult {
        public let text: String
        public let latencyMs: Int
    }

    private let apiKey: String
    private let session: URLSession
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"
    public static let requestTimeout: TimeInterval = 30.0

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Transcribe audio data using the Whisper API.
    public func transcribe(audioData: Data) async throws -> TranscriptionResult {
        let startTime = Date()

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.requestTimeout

        var body = Data()

        // Model field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\r\n\r\n".utf8))
        body.append(Data("gpt-4o-mini-transcribe\r\n".utf8))

        // Language hint — prevents misdetection cascades that cause hallucinations
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"language\"\r\n\r\n".utf8))
        body.append(Data("en\r\n".utf8))

        // Prompt — steers the model toward dictation-style output
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".utf8))
        body.append(Data("Voice dictation.\r\n".utf8))

        // Audio file — convert Float32 PCM to WAV
        let wavData = convertToWAV(audioData)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n".utf8))

        // Close boundary
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw TranscriptionError.noNetwork
        } catch {
            throw TranscriptionError.timeout
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.noNetwork
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                throw TranscriptionError.emptyResponse
            }
            return TranscriptionResult(text: text, latencyMs: latencyMs)
        case 401:
            throw TranscriptionError.apiKeyRejected
        case 429:
            throw TranscriptionError.rateLimited
        case 500...599:
            throw TranscriptionError.serverError
        default:
            throw TranscriptionError.noNetwork
        }
    }

    /// Convert raw Float32 PCM data to WAV format.
    private func convertToWAV(_ pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // Convert Float32 to Int16 PCM
        let floatCount = pcmData.count / MemoryLayout<Float>.size
        var int16Data = Data(count: floatCount * MemoryLayout<Int16>.size)
        pcmData.withUnsafeBytes { pcmPtr in
            int16Data.withUnsafeMutableBytes { int16Ptr in
                guard let pcmBase = pcmPtr.baseAddress,
                      let int16Base = int16Ptr.baseAddress else { return }
                let pcmFloat = pcmBase.assumingMemoryBound(to: Float.self)
                let int16Buf = int16Base.assumingMemoryBound(to: Int16.self)
                for i in 0..<floatCount {
                    let clamped = max(-1.0, min(1.0, pcmFloat[i]))
                    int16Buf[i] = Int16(clamped * 32767)
                }
            }
        }

        let dataSize = UInt32(int16Data.count)
        let fileSize = 36 + dataSize

        var wav = Data()
        // RIFF header
        wav.append(Data("RIFF".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wav.append(Data("WAVE".utf8))
        // fmt chunk
        wav.append(Data("fmt ".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        wav.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        // data chunk
        wav.append(Data("data".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        wav.append(int16Data)

        return wav
    }
}
