import Accelerate
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
    private var didFireNearLimit = false
    private var didHitLimit = false

    /// Maximum recording duration in seconds.
    private let maxDuration: TimeInterval = 60
    /// Warning threshold in seconds (fires `onNearLimit` once).
    private let nearLimitThreshold: TimeInterval = 50

    /// Called on the main queue when recording is auto-stopped at the duration cap.
    public var onAutoStop: (() -> Void)?
    /// Called on the main queue once when recording approaches the duration cap (~50s).
    public var onNearLimit: (() -> Void)?
    /// Spectrum callback — fires on the audio thread with `bandCount` normalised
    /// frequency-band magnitudes (0...1), low frequency first. Drives the equalizer overlay.
    public var onSpectrum: (([Float]) -> Void)?
    /// Called on the main queue when the input device changes mid-recording
    /// (AirPods connect/disconnect, mic unplugged). The engine has stopped by
    /// then, so the caller should stop and use what was captured.
    public var onInputChanged: (() -> Void)?

    private var configChangeObserver: NSObjectProtocol?

    /// Target sample rate for Whisper (16kHz mono)
    private let targetSampleRate: Double = 16000

    // MARK: - FFT spectrum analysis

    /// Number of frequency bands emitted (low → high). The overlay mirrors these
    /// across its bars (bass in the centre, treble at the edges).
    private let bandCount = 5
    /// FFT window size in samples (power of two).
    private let fftSize = 1024
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?
    private let hannWindow: [Float]
    /// Precomputed [lo, hi) magnitude-bin range for each band (log-spaced).
    private let bandBinRanges: [(Int, Int)]
    /// Per-band smoothed magnitudes (attack-fast / decay-slow), audio-thread only.
    private var smoothedBands: [Float]
    /// Master gain applied before the perceptual sqrt compression. Tunable by ear.
    private let masterGain: Float = 0.08

    public init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        hannWindow = window

        smoothedBands = [Float](repeating: 0, count: bandCount)

        // Log-spaced frequency bands across the speech range.
        let binHz = Float(targetSampleRate) / Float(fftSize)
        let nyquistBins = fftSize / 2
        let freqLow: Float = 110
        let freqHigh: Float = 5500
        var ranges: [(Int, Int)] = []
        for b in 0..<bandCount {
            let f0 = freqLow * powf(freqHigh / freqLow, Float(b) / Float(bandCount))
            let f1 = freqLow * powf(freqHigh / freqLow, Float(b + 1) / Float(bandCount))
            let lo = max(1, min(nyquistBins - 1, Int(f0 / binHz)))
            let hi = max(lo + 1, min(nyquistBins, Int(f1 / binHz)))
            ranges.append((lo, hi))
        }
        bandBinRanges = ranges
    }

    deinit {
        if isRecording {
            _ = stopRecording()
        }
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    /// Start capturing audio into the RAM buffer.
    public func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRecording else { return }

        audioBuffer = Data()
        startTime = Date()
        didFireNearLimit = false
        didHitLimit = false

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
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.appendBuffer(buffer)
            }
        } else {
            // No usable input device gives a format the converter can't take.
            guard let formatConverter = AVAudioConverter(from: hardwareFormat, to: recordingFormat) else {
                throw RecorderError.audioEngineError("no usable microphone")
            }
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
            let started = Date()
            configChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                // Bluetooth devices can fire one right as the engine starts.
                guard Date().timeIntervalSince(started) > 0.3 else { return }
                self?.onInputChanged?()
            }
        } catch {
            throw RecorderError.audioEngineError(error.localizedDescription)
        }
    }

    /// Stop capturing and return the accumulated audio data.
    public func stopRecording() -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard isRecording else { return Data() }

        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
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

        guard isRecording, !didHitLimit else { return }

        // Check elapsed time for near-limit warning and hard cap.
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)

            if elapsed >= maxDuration {
                didHitLimit = true
                let callback = onAutoStop
                DispatchQueue.main.async { callback?() }
                return
            }

            if !didFireNearLimit && elapsed >= nearLimitThreshold {
                didFireNearLimit = true
                let callback = onNearLimit
                DispatchQueue.main.async { callback?() }
            }
        }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
        audioBuffer.append(data)

        emitSpectrum(channelData, frameLength: frameLength)
    }

    /// Runs a real FFT over the latest samples and emits smoothed per-band
    /// magnitudes via `onSpectrum`. Called on the audio thread with `lock` held.
    private func emitSpectrum(_ channelData: UnsafePointer<Float>, frameLength: Int) {
        guard let fftSetup else { return }
        let n = fftSize
        let half = n / 2

        // Apply a Hann window over up to `n` samples (zero-padded if shorter).
        var windowed = [Float](repeating: 0, count: n)
        let take = min(frameLength, n)
        vDSP_vmul(channelData, 1, hannWindow, 1, &windowed, 1, vDSP_Length(take))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var bands = [Float](repeating: 0, count: bandCount)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Pack the real input into split-complex form, then forward FFT.
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Float](repeating: 0, count: half)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))

                for b in 0..<bandCount {
                    let (lo, hi) = bandBinRanges[b]
                    var sum: Float = 0
                    magnitudes.withUnsafeBufferPointer { magPtr in
                        vDSP_sve(magPtr.baseAddress! + lo, 1, &sum, vDSP_Length(hi - lo))
                    }
                    let avg = sum / Float(hi - lo)
                    // Lift higher bands (less energy) and compress perceptually.
                    let gain = 1.0 + 1.6 * Float(b) / Float(max(1, bandCount - 1))
                    bands[b] = min(1.0, sqrtf(avg * gain * masterGain))
                }
            }
        }

        // Attack fast, decay slow — classic equalizer ballistics.
        for i in 0..<bandCount {
            let target = bands[i]
            let rate: Float = target > smoothedBands[i] ? 0.55 : 0.22
            smoothedBands[i] += (target - smoothedBands[i]) * rate
        }

        onSpectrum?(smoothedBands)
    }
}
