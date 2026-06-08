import AppKit

/// A floating pill overlay (Wispr Flow–style) that shows recording state.
/// States: recording (pulsing red) → transcribing (spinning) → done (green check, auto-dismiss).
final class RecordingOverlay {

    enum State {
        case recording
        case transcribing
        case done
        case error(String)
    }

    private var window: NSWindow?
    private var contentView: OverlayPillView?
    private var animationTimer: Timer?
    private var dismissTimer: Timer?

    func show() {
        guard window == nil else { return }
        setState(.recording)
    }

    func hide() {
        setState(.done)
    }

    func showError(_ message: String) {
        setState(.error(message))
    }

    func showTranscribing() {
        setState(.transcribing)
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
            ensureWindow()
            contentView?.state = .recording
            startAnimation()

        case .transcribing:
            ensureWindow()
            contentView?.state = .transcribing
            startAnimation()

        case .done:
            guard window != nil else { return }
            animationTimer?.invalidate()
            animationTimer = nil
            contentView?.state = .done
            contentView?.needsDisplay = true
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                self?.tearDown()
            }

        case .error(let msg):
            ensureWindow()
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

    private func ensureWindow() {
        guard window == nil else { return }

        let width: CGFloat = 160
        let height: CGFloat = 40

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
        win.contentView = pill

        window = win
        contentView = pill
        win.orderFront(nil)
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let view = self?.contentView else { return }
            view.animationPhase += 0.08
            if view.animationPhase > .pi * 2 {
                view.animationPhase -= .pi * 2
            }
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
    }
}

private class OverlayPillView: NSView {

    enum DisplayState {
        case recording
        case transcribing
        case done
        case error
    }

    var state: DisplayState = .recording
    var animationPhase: CGFloat = 0
    var errorMessage: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let pill = bounds.insetBy(dx: 2, dy: 2)
        let radius = pill.height / 2
        let path = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Background
        ctx.setFillColor(NSColor(white: 0.1, alpha: 0.92).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // Border
        ctx.setStrokeColor(NSColor(white: 0.3, alpha: 0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path)
        ctx.strokePath()

        switch state {
        case .recording:
            drawRecording(ctx)
        case .transcribing:
            drawTranscribing(ctx)
        case .done:
            drawDone(ctx)
        case .error:
            drawError(ctx)
        }
    }

    private func drawRecording(_ ctx: CGContext) {
        let pulse = (sin(animationPhase) + 1) / 2
        let center = CGPoint(x: 22, y: bounds.midY)

        // Glow
        let glowR: CGFloat = 10 * (0.8 + 0.2 * pulse)
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.25 * pulse).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))

        // Dot
        let r: CGFloat = 5 * (0.85 + 0.15 * pulse)
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        drawText("Listening...", at: 36, ctx: ctx, color: .white)
    }

    private func drawTranscribing(_ ctx: CGContext) {
        let center = CGPoint(x: 22, y: bounds.midY)
        let r: CGFloat = 7

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)

        let dotCount = 3
        for i in 0..<dotCount {
            let angle = animationPhase + CGFloat(i) * (.pi * 2 / CGFloat(dotCount))
            let x = cos(angle) * r
            let y = sin(angle) * r
            let alpha = 0.4 + 0.6 * CGFloat(i) / CGFloat(dotCount - 1)
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
        }

        ctx.restoreGState()

        drawText("Transcribing...", at: 36, ctx: ctx, color: NSColor(white: 0.8, alpha: 1))
    }

    private func drawDone(_ ctx: CGContext) {
        let center = CGPoint(x: 22, y: bounds.midY)

        // Green circle
        let r: CGFloat = 7
        ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.2).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        // Checkmark
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: center.x - 3.5, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x - 1, y: center.y - 3))
        ctx.addLine(to: CGPoint(x: center.x + 4, y: center.y + 3))
        ctx.strokePath()

        drawText("Done", at: 36, ctx: ctx, color: NSColor.systemGreen)
    }

    private func drawError(_ ctx: CGContext) {
        let center = CGPoint(x: 22, y: bounds.midY)

        // Red circle
        let r: CGFloat = 7
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.2).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        // X mark
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
        let truncated = msg.count > 18 ? String(msg.prefix(18)) + "…" : msg
        drawText(truncated, at: 36, ctx: ctx, color: NSColor.systemRed)
    }

    private func drawText(_ text: String, at x: CGFloat, ctx: CGContext, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: x, y: bounds.midY - size.height / 2, width: bounds.width - x - 8, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}
