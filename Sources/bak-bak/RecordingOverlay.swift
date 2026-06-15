import AppKit
import SwiftUI

final class RecordingOverlay {
    
    private var window: NSWindow?
    private var dismissTimer: Timer?
    private var pendingRecordingDuration: TimeInterval = 0
    private let viewModel = OverlayViewModel()
    
    func show() {
        guard window == nil else { return }
        setState(.recording)
    }
    
    func hide() {
        viewModel.doneText = ""
        setState(.done)
    }
    
    func showDone(text: String) {
        viewModel.doneText = text
        setState(.done)
    }
    
    func showError(_ message: String) {
        viewModel.errorMessage = message
        setState(.error)
    }
    
    func showTranscribing(recordingDuration: TimeInterval = 0) {
        pendingRecordingDuration = recordingDuration
        setState(.transcribing)
    }
    
    func showDiscarded() {
        setState(.discarded)
    }
    
    func showNearLimit() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.isNearLimit = true
        }
    }
    
    func injectSpectrum(_ bands: [Float]) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.linear(duration: 0.08)) {
                self?.viewModel.bands = bands
            }
        }
    }
    
    private func setState(_ state: OverlayViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            self?.applyState(state)
        }
    }
    
    private func applyState(_ state: OverlayViewModel.State) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        switch state {
        case .recording:
            ensureWindow()
            viewModel.bands = OverlayViewModel.emptyBands
            viewModel.isNearLimit = false
            viewModel.doneText = ""
            viewModel.state = .recording

        case .transcribing:
            ensureWindow()
            viewModel.recordingDuration = pendingRecordingDuration
            viewModel.transcribingStartDate = Date()
            viewModel.state = .transcribing

        case .done:
            guard window != nil else { return }
            viewModel.state = .done
            let text = viewModel.doneText
            let displayDuration: TimeInterval = text.isEmpty ? 0.6 : 1.5
            dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
                self?.tearDown()
            }

        case .discarded:
            guard window != nil else { return }
            viewModel.state = .discarded
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.tearDown()
            }

        case .error:
            ensureWindow()
            viewModel.state = .error
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.tearDown()
            }
        }
    }
    
    private func ensureWindow() {
        guard window == nil else { return }

        // Create a window large enough to contain the spring animation width expansions
        let windowWidth: CGFloat = 400
        let height: CGFloat = 80 

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - windowWidth / 2
        let y = screen.frame.maxY - height - 60

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating + 1
        win.isOpaque = false
        win.backgroundColor = .clear // Passthrough for clicks on transparent areas
        win.hasShadow = true         // macOS adds dropshadow to non-clear views
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = false

        let hostingView = NSHostingView(rootView: OverlayContainerView(viewModel: viewModel))
        win.contentView = hostingView

        window = win
        win.orderFront(nil)
    }
    
    private func tearDown() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil
        viewModel.doneText = ""
    }
}

// MARK: - SwiftUI Views and ViewModel

final class OverlayViewModel: ObservableObject {
    enum State: Equatable {
        case recording
        case transcribing
        case done
        case discarded
        case error
    }

    /// Number of frequency bands emitted by the recorder (low → high).
    static let bandCount = 5
    static let emptyBands = [Float](repeating: 0, count: bandCount)

    @Published var state: State = .recording
    /// Per-band magnitudes (0...1), low frequency first.
    @Published var bands: [Float] = emptyBands
    @Published var isNearLimit: Bool = false

    /// Overall loudness used to drive the pill's glow-pulse.
    var overallLevel: Float { bands.max() ?? 0 }
    @Published var doneText: String = ""
    @Published var errorMessage: String = ""
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcribingStartDate: Date?
    
    var targetWidth: CGFloat {
        switch state {
        case .recording: return 210
        case .transcribing: return 240
        case .done: return doneText.isEmpty ? 180 : 320
        case .discarded: return 180
        case .error: return 180
        }
    }
}

struct OverlayContainerView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        OverlayPillView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OverlayPillView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        ZStack {
            if viewModel.state == .recording {
                glowLayer
            }

            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            Capsule()
                .stroke(borderColor.opacity(0.35), lineWidth: 0.5)

            Group {
                switch viewModel.state {
                case .recording:
                    recordingView
                case .transcribing:
                    transcribingView
                case .done:
                    doneView
                case .discarded:
                    discardedView
                case .error:
                    errorView
                }
            }
            .id(viewModel.state == .recording ? "recording" : "transition") 
        }
        .frame(width: viewModel.targetWidth, height: 44)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.doneText)
    }
    
    /// Soft halo behind the pill that breathes gently and swells with the voice.
    private var glowLayer: some View {
        TimelineView(.animation) { timeline in
            let idle = (sin(timeline.date.timeIntervalSince1970 * 2.2) + 1) / 2 * 0.15
            let intensity = min(1.0, idle + Double(viewModel.overallLevel))
            Capsule()
                .stroke(borderColor.opacity(0.25 + 0.45 * intensity), lineWidth: 1.0 + 1.5 * intensity)
                .blur(radius: 3 + 5 * intensity)
                .opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch viewModel.state {
        case .recording: return viewModel.isNearLimit ? .orange : .red
        case .transcribing: return .blue
        case .done: return .green
        case .discarded: return .gray
        case .error: return .red
        }
    }
    
    private var recordingView: some View {
        HStack(spacing: 8) {
            TimelineView(.animation) { timeline in
                let dotPulse = (sin(timeline.date.timeIntervalSince1970 * 4.5) + 1.0) / 2.0
                let dotR = 3.5 * (0.8 + 0.2 * dotPulse)
                let tintColor: Color = viewModel.isNearLimit ? .orange : .red
                
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tintColor.opacity(0.3 * dotPulse))
                            .frame(width: (dotR + 2) * 2, height: (dotR + 2) * 2)
                        Circle()
                            .fill(tintColor)
                            .frame(width: dotR * 2, height: dotR * 2)
                    }
                    .frame(width: 14)
                    
                    WaveformView(date: timeline.date, bands: viewModel.bands, isNearLimit: viewModel.isNearLimit, isFrozen: false)
                }
            }
            
            Text(viewModel.isNearLimit ? "Wrapping up..." : "Listening...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: NSColor(white: 0.85, alpha: 1)))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
    
    private var transcribingView: some View {
        HStack(spacing: 8) {
            TimelineView(.animation) { timeline in
                let elapsed = viewModel.transcribingStartDate.map { timeline.date.timeIntervalSince($0) } ?? 0
                let isFrozen = elapsed < 0.15
                
                HStack(spacing: 8) {
                    if isFrozen {
                        WaveformView(date: viewModel.transcribingStartDate ?? timeline.date, bands: viewModel.bands, isNearLimit: false, isFrozen: true)
                            .frame(width: 20)
                    } else {
                        SpinnerView(date: timeline.date)
                            .frame(width: 20)
                    }
                    
                    let durationStr = formatDuration(viewModel.recordingDuration)
                    let visibleElapsed = max(0, elapsed - 0.15)
                    let elapsedStr = formatDuration(visibleElapsed)
                    
                    HStack(spacing: 6) {
                        Text("Got \(durationStr)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(nsColor: NSColor(white: 0.5, alpha: 1)))
                        
                        Text(isFrozen ? "Captured" : "Transcribing")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue.opacity(0.9))
                        
                        if !isFrozen && visibleElapsed > 0.1 {
                            Text(elapsedStr)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.blue.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
    
    private var doneView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
            .frame(width: 24)
            
            if viewModel.doneText.isEmpty {
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Text(viewModel.doneText)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.88, alpha: 1)))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
    
    private var discardedView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.15)).frame(width: 16, height: 16)
                Image(systemName: "mic.slash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
            }
            .frame(width: 24)
            
            Text("No speech")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
    
    private var errorView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.red.opacity(0.15)).frame(width: 16, height: 16)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
            }
            .frame(width: 24)
            
            let message = viewModel.errorMessage.isEmpty ? "Error" : viewModel.errorMessage
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        return "\(Int(seconds.rounded()))s"
    }
}

// MARK: - Subcomponents

struct WaveformView: View {
    let date: Date
    /// Per-band magnitudes (0...1), low frequency first.
    let bands: [Float]
    let isNearLimit: Bool
    let isFrozen: Bool

    let barCount = 9
    let barWidth: CGFloat = 3
    let barSpacing: CGFloat = 3.5
    let maxBarHeight: CGFloat = 18

    var body: some View {
        let tintColor: Color = isNearLimit ? .orange : (isFrozen ? .blue : .red)
        // Fast secondary oscillation keeps the bars alive between FFT frames.
        let phase = isFrozen ? 0 : date.timeIntervalSince1970 * 6.0

        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let band = bandValue(forBar: i)
                let shimmer = isFrozen ? 0 : (sin(phase + Double(i) * 0.9) + 1) / 2 * 0.12
                let mag = min(1.0, band + shimmer)
                let barH = max(3.0, maxBarHeight * mag)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tintColor.opacity(0.55), tintColor],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: barH)
                    .shadow(color: tintColor.opacity(isFrozen ? 0 : 0.6 * mag), radius: 2.5 * mag)
            }
        }
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing, height: 20)
    }

    /// Mirror-symmetric mapping: centre bar = bass, outer bars = treble.
    private func bandValue(forBar i: Int) -> Double {
        guard !bands.isEmpty else { return 0 }
        let center = (barCount - 1) / 2
        let idx = min(bands.count - 1, abs(i - center))
        return Double(bands[idx])
    }
}

struct SpinnerView: View {
    let date: Date
    
    var body: some View {
        let phase = date.timeIntervalSince1970 * 3.6
        let orbitR: CGFloat = 7.0
        
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let angle = phase + Double(i) * (.pi * 2 / 4)
                let x = cos(angle) * orbitR
                let y = sin(angle) * orbitR
                let alpha = 0.3 + 0.7 * Double(i) / 3.0
                let dotR: CGFloat = 2.5 - CGFloat(i) * 0.3
                
                Circle()
                    .fill(Color.blue.opacity(alpha))
                    .frame(width: dotR * 2, height: dotR * 2)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: 20, height: 20)
    }
}
