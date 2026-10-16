import AVFoundation

/// Reads an audio file (wav, aiff, m4a, mp3, flac, …) into the same format
/// `AudioRecorder` produces: 16 kHz mono Float32 PCM. Used by
/// `bak-bak transcribe` to run a file through the real pipeline.
public enum AudioFileLoader {

    public enum LoadError: Error, LocalizedError {
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return "Couldn't read audio: \(detail)"
            }
        }
    }

    public static let sampleRate: Double = 16_000

    public static func loadPCM(from url: URL) throws -> Data {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }

        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LoadError.unreadable("unsupported format")
        }
        try file.read(into: input)

        let ratio = sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw LoadError.unreadable("couldn't allocate buffer")
        }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw LoadError.unreadable(conversionError.localizedDescription) }

        guard let samples = output.floatChannelData?[0] else { throw LoadError.unreadable("no samples") }
        return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Float>.size)
    }
}
