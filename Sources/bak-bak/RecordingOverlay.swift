import AppKit

final class RecordingOverlay {

    enum State {
        case recording
        case transcribing
        case done
        case discarded
        case error(String)
    }

    private var window: NSWindow?
    private var contentView: OverlayPillView?
    private var animationTimer: Timer?
    private var dismissTimer: Timer?
    private var doneText: String = ""
    private var pendingRecordingDuration: TimeInterval = 0

    func show() {
        guard window == nil else { return }
        setState(.recording)
    }

    func hide() {
        doneText = ""
        setState(.done)
    }

    func showDone(text: String) {
        doneText = text
        setState(.done)
    }

    func showError(_ message: String) {
        setState(.error(message))
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
            self?.contentView?.isNearLimit = true
        }
    }

    func injectAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.contentView?.rawLevel = level
        }
    }

    private func setState(_ state: State) {
        DispatchQueue.main.async { [weak self] in
            self?.applyState(state)
        }
    }

    private func applyState(_ state: State) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        switch state {
        case .recording:
            ensureWindow(width: 180)
            setWindowWidth(180)
            contentView?.rawLevel = 0
            contentView?.smoothedLevel = 0
            contentView?.isNearLimit = false
            contentView?.doneText = ""
            contentView?.state = .recording
            startAnimation()

        case .transcribing:
            ensureWindow(width: 240)
            setWindowWidth(240)
            contentView?.rawLevel = 0
            contentView?.smoothedLevel = 0
            contentView?.recordingDuration = pendingRecordingDuration
            contentView?.transcribingStartDate = Date()
            contentView?.state = .transcribing
            startAnimation()

        case .done:
            guard window != nil else { return }
            animationTimer?.invalidate()
            animationTimer = nil
            let text = doneText
            let targetWidth: CGFloat = text.isEmpty ? 180 : 280
            setWindowWidth(targetWidth, animate: !text.isEmpty)
            contentView?.doneText = text
            contentView?.state = .done
            contentView?.needsDisplay = true
            let displayDuration: TimeInterval = text.isEmpty ? 0.6 : 1.5
            dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
                self?.tearDown()
            }

        case .discarded:
            guard window != nil else { return }
            animationTimer?.invalidate()
            animationTimer = nil
            contentView?.state = .discarded
            contentView?.needsDisplay = true
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.tearDown()
            }

        case .error(let msg):
            ensureWindow(width: 180)
            setWindowWidth(180)
            animationTimer?.invalidate()
            animationTimer = nil
            contentView?.errorMessage = msg
            contentView?.state = .error
            contentView?.needsDisplay = true
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.tearDown()
            }
        }
    }

    private func ensureWindow(width: CGFloat) {
        guard window == nil else { return }

        let height: CGFloat = 44

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height - 60

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating + 1
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = false

        let pill = OverlayPillView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        pill.autoresizingMask = [.width, .height]
        win.contentView = pill

        window = win
        contentView = pill
        win.orderFront(nil)
    }

    private func setWindowWidth(_ width: CGFloat, animate: Bool = false) {
        guard let win = window, let screen = NSScreen.main else { return }
        guard abs(win.frame.width - width) > 1 else { return }
        let newX = screen.frame.midX - width / 2
        let newFrame = NSRect(x: newX, y: win.frame.minY, width: width, height: 44)
        win.setFrame(newFrame, display: true, animate: animate)
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, let view = self.contentView else { return }
            view.animationPhase += 0.1
            if view.animationPhase > .pi * 2 {
                view.animationPhase -= .pi * 2
            }
            view.smoothedLevel += (view.rawLevel - view.smoothedLevel) * 0.3
            view.needsDisplay = true
        }
    }

    private func tearDown() {
        animationTimer?.invalidate()
        animationTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil
        contentView = nil
        doneText = ""
    }
}

// MARK: - OverlayPillView

private class OverlayPillView: NSView {

    enum DisplayState {
        case recording
        case transcribing
        case done
        case discarded
        case error
    }

    var state: DisplayState = .recording
    var animationPhase: CGFloat = 0
    var errorMessage: String = ""
    var rawLevel: Float = 0
    var smoothedLevel: Float = 0
    var isNearLimit = false
    var doneText: String = ""
    var recordingDuration: TimeInterval = 0
    var transcribingStartDate: Date?

    private let barCount = 9
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3.5
    private let maxBarHeight: CGFloat = 18

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let pill = bounds.insetBy(dx: 2, dy: 2)
        let radius = pill.height / 2
        let path = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.94).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        let borderColor: NSColor
        switch state {
        case .recording: borderColor = (isNearLimit ? NSColor.systemOrange : NSColor.systemRed).withAlphaComponent(0.35)
        case .transcribing: borderColor = NSColor.systemBlue.withAlphaComponent(0.35)
        case .done: borderColor = NSColor.systemGreen.withAlphaComponent(0.35)
        case .discarded: borderColor = NSColor.systemGray.withAlphaComponent(0.35)
        case .error: borderColor = NSColor.systemRed.withAlphaComponent(0.35)
        }
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path)
        ctx.strokePath()

        switch state {
        case .recording: drawRecording(ctx)
        case .transcribing: drawTranscribing(ctx)
        case .done: drawDone(ctx)
        case .discarded: drawDiscarded(ctx)
        case .error: drawError(ctx)
        }
    }

    // MARK: - Recording (Live Waveform)

    private func drawRecording(_ ctx: CGContext) {
        let tintColor: NSColor = isNearLimit ? .systemOrange : .systemRed
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX: CGFloat = 20
        let centerY = bounds.midY
        let level = CGFloat(smoothedLevel)

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let phase = animationPhase + CGFloat(i) * 0.7
            let wave = (sin(phase) + 1) / 2
            let combined = wave * 0.4 + level * 0.6
            let barH = max(3, maxBarHeight * combined)

            let barRect = CGRect(x: x, y: centerY - barH / 2, width: barWidth, height: barH)
            let barRadius = barWidth / 2
            let barPath = CGPath(roundedRect: barRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)

            let alpha = CGFloat(0.5 + 0.5 * combined)
            ctx.setFillColor(tintColor.withAlphaComponent(alpha).cgColor)
            ctx.addPath(barPath)
            ctx.fillPath()

            if combined > 0.4 {
                let glowAlpha = CGFloat((combined - 0.4) * 0.4)
                ctx.setFillColor(tintColor.withAlphaComponent(glowAlpha).cgColor)
                let glowRect = barRect.insetBy(dx: -2, dy: -2)
                let glowPath = CGPath(roundedRect: glowRect, cornerWidth: barRadius + 2, cornerHeight: barRadius + 2, transform: nil)
                ctx.addPath(glowPath)
                ctx.fillPath()
            }
        }

        let dotPulse = (sin(animationPhase * 1.5) + 1) / 2
        let dotR: CGFloat = 3.5 * (0.8 + 0.2 * dotPulse)
        let dotCenter = CGPoint(x: 10, y: centerY)
        ctx.setFillColor(tintColor.withAlphaComponent(0.3 * dotPulse).cgColor)
        ctx.fillEllipse(in: CGRect(x: dotCenter.x - dotR - 2, y: dotCenter.y - dotR - 2, width: (dotR + 2) * 2, height: (dotR + 2) * 2))
        ctx.setFillColor(tintColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2))

        let label = isNearLimit ? "Wrapping up..." : "Listening..."
        drawText(label, at: startX + totalWidth + 8, ctx: ctx, color: NSColor(white: 0.85, alpha: 1))
    }

    // MARK: - Transcribing

    private func drawTranscribing(_ ctx: CGContext) {
        let elapsed = transcribingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let isFrozen = elapsed < 0.15

        let centerX: CGFloat = 20
        let centerY = bounds.midY

        if isFrozen {
            // Waveform freeze: show the captured audio shape briefly before the spinner
            drawFrozenWaveform(ctx)
        } else {
            let orbitR: CGFloat = 7
            ctx.saveGState()
            ctx.translateBy(x: centerX, y: centerY)
            for i in 0..<4 {
                let angle = animationPhase * 1.2 + CGFloat(i) * (.pi * 2 / 4)
                let x = cos(angle) * orbitR
                let y = sin(angle) * orbitR
                let alpha = 0.3 + 0.7 * CGFloat(i) / 3.0
                let dotR: CGFloat = 2.5 - CGFloat(i) * 0.3
                ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
            }
            ctx.restoreGState()
        }

        // "Got 4.2s  Transcribing  1.2s" — confirms audio was captured + shows live elapsed
        let durationStr = formatDuration(recordingDuration)
        let visibleElapsed = max(0, elapsed - 0.15)
        let elapsedStr = formatDuration(visibleElapsed)

        let label = NSMutableAttributedString()
        label.append(NSAttributedString(
            string: "Got \(durationStr)  ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 0.5, alpha: 1)
            ]
        ))
        label.append(NSAttributedString(
            string: isFrozen ? "Captured" : "Transcribing",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.9)
            ]
        ))
        if !isFrozen && visibleElapsed > 0 {
            label.append(NSAttributedString(
                string: "  \(elapsedStr)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.5)
                ]
            ))
        }

        let labelSize = label.size()
        let labelRect = CGRect(
            x: 36,
            y: centerY - labelSize.height / 2,
            width: bounds.width - 44,
            height: labelSize.height
        )
        label.draw(in: labelRect)
    }

    private func drawFrozenWaveform(_ ctx: CGContext) {
        let tintColor = NSColor.systemBlue
        let startX: CGFloat = 8
        let centerY = bounds.midY
        let level = CGFloat(smoothedLevel)

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let phase = CGFloat(i) * 0.7
            let wave = (sin(phase) + 1) / 2
            let combined = wave * 0.4 + level * 0.6
            let barH = max(3, maxBarHeight * combined)

            let barRect = CGRect(x: x, y: centerY - barH / 2, width: barWidth, height: barH)
            let barRadius = barWidth / 2
            let barPath = CGPath(roundedRect: barRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
            ctx.setFillColor(tintColor.withAlphaComponent(CGFloat(0.4 + 0.4 * combined)).cgColor)
            ctx.addPath(barPath)
            ctx.fillPath()
        }
    }

    // MARK: - Done

    private func drawDone(_ ctx: CGContext) {
        let center = CGPoint(x: 20, y: bounds.midY)
        let r: CGFloat = 8
        ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.15).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: center.x - 3.5, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x - 0.5, y: center.y - 3))
        ctx.addLine(to: CGPoint(x: center.x + 4, y: center.y + 3))
        ctx.strokePath()

        if doneText.isEmpty {
            drawText("Done", at: 36, ctx: ctx, color: NSColor.systemGreen)
        } else {
            let maxChars = 32
            let snippet = doneText.count > maxChars
                ? String(doneText.prefix(maxChars)) + "\u{2026}"
                : doneText
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.88, alpha: 1)
            ]
            let size = (snippet as NSString).size(withAttributes: attrs)
            let rect = CGRect(x: 36, y: bounds.midY - size.height / 2, width: bounds.width - 44, height: size.height)
            (snippet as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    // MARK: - Discarded

    private func drawDiscarded(_ ctx: CGContext) {
        let center = CGPoint(x: 24, y: bounds.midY)
        let r: CGFloat = 8
        ctx.setFillColor(NSColor.systemGray.withAlphaComponent(0.15).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        ctx.setStrokeColor(NSColor.systemGray.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: center.x, y: center.y - 4))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + 4))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: center.x - 4, y: center.y + 4))
        ctx.addLine(to: CGPoint(x: center.x + 4, y: center.y - 4))
        ctx.strokePath()

        drawText("No speech", at: 40, ctx: ctx, color: NSColor.systemGray)
    }

    // MARK: - Error

    private func drawError(_ ctx: CGContext) {
        let center = CGPoint(x: 24, y: bounds.midY)
        let r: CGFloat = 8
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.15).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: center.x - 3, y: center.y - 3))
        ctx.addLine(to: CGPoint(x: center.x + 3, y: center.y + 3))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: center.x + 3, y: center.y - 3))
        ctx.addLine(to: CGPoint(x: center.x - 3, y: center.y + 3))
        ctx.strokePath()

        let msg = errorMessage.isEmpty ? "Error" : errorMessage
        let truncated = msg.count > 16 ? String(msg.prefix(16)) + "\u{2026}" : msg
        drawText(truncated, at: 40, ctx: ctx, color: NSColor.systemRed)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        return "\(Int(seconds.rounded()))s"
    }

    private func drawText(_ text: String, at x: CGFloat, ctx: CGContext, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: x, y: bounds.midY - size.height / 2, width: bounds.width - x - 8, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}
