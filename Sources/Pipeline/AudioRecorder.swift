import AVFoundation
import Foundation

/// Captures audio from the microphone into an in-RAM buffer.
/// Audio is never written to disk — flushed on release, discarded after transcription.
/// Records at 16kHz mono (Whisper's expected format).
public final class AudioRecorder: @unchecked Sendable {

    public enum RecorderError: Error, LocalizedError {
        case audioEngineError(String)
        case recordingTooLong
        case microphoneAccessDenied

        public var errorDescription: String? {
            switch self {
            case .audioEngineError(let reason): return reason
            case .recordingTooLong: return "recording too long"
            case .microphoneAccessDenied: return "mic access denied"
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var audioBuffer = Data()
    private var isRecording = false
    private let lock = NSLock()
    private var startTime: Date?

    /// Target sample rate for Whisper (16kHz mono)
    private let targetSampleRate: Double = 16000

    public init() {}

    deinit {
        if isRecording {
            _ = stopRecording()
        }
    }

    /// Start capturing audio into the RAM buffer.
    public func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRecording else { return }

        audioBuffer = Data()
        startTime = Date()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Configure for 16kHz mono — Whisper's expected format
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        if hardwareFormat.sampleRate == targetSampleRate && hardwareFormat.channelCount == 1 {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                self?.appendBuffer(buffer)
            }
        } else {
            let formatConverter = AVAudioConverter(from: hardwareFormat, to: recordingFormat)!
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * (recordingFormat.sampleRate / buffer.format.sampleRate)
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: recordingFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                let status = formatConverter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status == .haveData {
                    self?.appendBuffer(convertedBuffer)
                }
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
        } catch {
            throw RecorderError.audioEngineError(error.localizedDescription)
        }
    }

    /// Stop capturing and return the accumulated audio data.
    public func stopRecording() -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard isRecording else { return Data() }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let data = audioBuffer
        audioBuffer = Data()
        startTime = nil

        return data
    }

    public var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecording
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isRecording else { return }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
        audioBuffer.append(data)
    }
}
