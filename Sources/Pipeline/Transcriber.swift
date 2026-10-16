import AudioToolbox
import Foundation

/// Anything that can turn recorded audio (16 kHz mono Float32 PCM) into text.
/// Today that's `Transcriber` for OpenAI-compatible services; an on-device
/// engine can slot in later without touching the rest of the pipeline.
public protocol TranscriptionEngine: Sendable {
    func transcribe(audioData: Data) async throws -> Transcriber.TranscriptionResult
}

/// Sends audio to an OpenAI-compatible `/audio/transcriptions` endpoint
/// (OpenAI, Groq, …) in a single multipart POST. No SDK. Measures round-trip
/// latency for `doctor`.
public final class Transcriber: TranscriptionEngine, @unchecked Sendable {

    public enum TranscriptionError: Error, LocalizedError, Equatable {
        case noNetwork
        case timeout
        case network(String)
        case apiKeyRejected(host: String)
        case rateLimited
        case serverError(Int)
        case badRequest(String)
        case modelNotFound(String)
        case invalidEndpoint(String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .noNetwork: return "No internet connection"
            case .timeout: return "Transcription timed out"
            case .network(let detail): return "Network error: \(detail)"
            case .apiKeyRejected(let host): return "API key rejected by \(host)"
            case .rateLimited: return "Rate limited or out of credit"
            case .serverError(let code): return "Transcription service error (\(code))"
            case .badRequest(let detail): return "Request rejected: \(detail)"
            case .modelNotFound(let detail): return "Model not found: \(detail)"
            case .invalidEndpoint(let url): return "Not a valid service URL: \(url)"
            case .emptyResponse: return "The service sent back no text"
            }
        }
    }

    public struct TranscriptionResult {
        public let text: String
        public let latencyMs: Int
    }

    private let apiKey: String
    private let prompt: String
    private let config: TranscriptionConfig
    private let session: URLSession
    public static let requestTimeout: TimeInterval = 30.0

    /// - Parameter prompt: context for the model; see `TranscriptionPrompt`.
    public init(
        apiKey: String,
        prompt: String = TranscriptionPrompt.base,
        config: TranscriptionConfig = .default,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.prompt = prompt
        self.config = config
        self.session = session
    }

    public func transcribe(audioData: Data) async throws -> TranscriptionResult {
        guard let endpoint = config.endpoint else {
            throw TranscriptionError.invalidEndpoint(config.baseURL)
        }
        let startTime = Date()

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.requestTimeout

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        field("model", config.model)
        // Language hint — prevents misdetection cascades that cause
        // hallucinations. Left out for Hinglish/auto so the model can detect.
        if let code = config.language.apiCode {
            field("language", code)
        }
        // Prompt — steers the model toward dictation-style output and the
        // user's vocabulary
        field("prompt", prompt)

        // Audio file — convert Float32 PCM to FLAC (falls back to WAV on failure)
        let audioFileData = convertToFLAC(audioData)
        let isFlac = audioFileData != nil
        let fileData = audioFileData ?? convertToWAV(audioData)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(isFlac ? "flac" : "wav")\"\r\n".utf8))
        body.append(Data("Content-Type: audio/\(isFlac ? "flac" : "wav")\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.network("no HTTP response")
        }
        return try Self.parse(statusCode: httpResponse.statusCode, body: data, host: config.host, latencyMs: latencyMs)
    }

    // MARK: - Response handling

    static func map(_ error: URLError) -> TranscriptionError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
            return .noNetwork
        default:
            return .network(error.localizedDescription)
        }
    }

    static func parse(statusCode: Int, body: Data, host: String, latencyMs: Int) throws -> TranscriptionResult {
        switch statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let text = json["text"] as? String else {
                throw TranscriptionError.emptyResponse
            }
            return TranscriptionResult(text: text, latencyMs: latencyMs)
        case 401, 403:
            throw TranscriptionError.apiKeyRejected(host: host)
        case 404:
            throw TranscriptionError.modelNotFound(errorMessage(in: body) ?? "HTTP 404")
        case 429:
            throw TranscriptionError.rateLimited
        case 500...599:
            throw TranscriptionError.serverError(statusCode)
        default:
            throw TranscriptionError.badRequest(errorMessage(in: body) ?? "HTTP \(statusCode)")
        }
    }

    /// OpenAI-style `{"error": {"message": "..."}}`.
    private static func errorMessage(in body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String, !message.isEmpty else { return nil }
        return message
    }

    /// Convert raw Float32 PCM data to FLAC format using AudioToolbox.
    /// Returns nil if FLAC encoding fails (caller should fall back to WAV).
    private func convertToFLAC(_ pcmData: Data) -> Data? {
        let sampleRate: Float64 = 16000
        let channels: UInt32 = 1

        // Input format: Float32 PCM (matches AudioRecorder output)
        var inputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        // Output format: FLAC
        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatFLAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        // Let AudioToolbox fill in the remaining output format details
        var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &propSize, &outputFormat)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".flac")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create the output FLAC file
        var outputFile: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            tempURL as CFURL,
            kAudioFileFLACType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        )
        guard status == noErr, let outFile = outputFile else { return nil }

        // Tell ExtAudioFile that the client data is Float32 PCM
        status = ExtAudioFileSetProperty(
            outFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &inputFormat
        )
        guard status == noErr else {
            ExtAudioFileDispose(outFile)
            return nil
        }

        // Write all PCM frames
        let frameCount = UInt32(pcmData.count / MemoryLayout<Float>.size)
        let writeStatus: OSStatus = pcmData.withUnsafeBytes { rawPtr in
            let buffer = AudioBuffer(
                mNumberChannels: channels,
                mDataByteSize: UInt32(pcmData.count),
                mData: UnsafeMutableRawPointer(mutating: rawPtr.baseAddress!)
            )
            var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
            return ExtAudioFileWrite(outFile, frameCount, &bufferList)
        }

        // Dispose to flush all data to disk
        ExtAudioFileDispose(outFile)

        guard writeStatus == noErr else { return nil }
        guard let flacData = try? Data(contentsOf: tempURL) else { return nil }
        return flacData
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
