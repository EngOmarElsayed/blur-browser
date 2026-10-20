import AppKit
import QuartzCore

/// Implemented by whatever hosts the web view (`WebViewController`), so the
/// agent's tools can find the overlay for a given `WKWebView` through the
/// responder chain.
@MainActor
protocol AgentActionHosting: AnyObject {
    /// The overlay covering the web content, raised above everything else.
    func agentActionOverlay() -> AgentActionOverlay
}

/// Sits on top of the web view while the agent acts. It draws the virtual
/// cursor, click ripples and a status label, and while `isBlocking` it
/// swallows the user's mouse so they can't fight the agent mid-action
/// (like `BlockingDimView`, but without dimming).
///
/// The agent's own events never pass through here: they're delivered straight
/// to the `WKWebView`, so the real system cursor never moves.
final class AgentActionOverlay: NSView {
    private let cursorLayer = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")
    private let labelBackground = NSVisualEffectView()
    private var hideCursorWork: DispatchWorkItem?

    /// True while an action runs; mouse events over the page are swallowed.
    private(set) var isBlocking = false

    /// Where the cursor's tip is, in this view's (flipped) coordinates.
    private(set) var cursorPoint: NSPoint?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]

        cursorLayer.path = Self.arrowPath()
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 16, height: 22)
        cursorLayer.anchorPoint = .zero
        cursorLayer.lineWidth = 1.5
        cursorLayer.lineJoin = .round
        cursorLayer.shadowColor = NSColor.black.cgColor
        cursorLayer.shadowOpacity = 0.35
        cursorLayer.shadowRadius = 2.5
        cursorLayer.shadowOffset = CGSize(width: 0, height: 1.5)
        cursorLayer.opacity = 0
        cursorLayer.zPosition = 10
        layer?.addSublayer(cursorLayer)

        labelBackground.material = .hudWindow
        labelBackground.blendingMode = .withinWindow
        labelBackground.state = .active
        labelBackground.wantsLayer = true
        labelBackground.layer?.cornerRadius = 11
        labelBackground.layer?.cornerCurve = .continuous
        labelBackground.isHidden = true
        addSubview(labelBackground)

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        labelBackground.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isBlocking, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    // MARK: - Session

    /// Starts blocking the mouse and shows `status` ("Agent is typing…").
    func begin(status: String, showCursor: Bool) {
        hideCursorWork?.cancel()
        isBlocking = true
        applyColors()
        label.stringValue = status
        labelBackground.isHidden = false
        layoutLabel()
        if showCursor {
            if cursorPoint == nil { placeCursor(at: NSPoint(x: bounds.midX, y: bounds.midY)) }
            setCursorVisible(true)
        }
    }

    func setStatus(_ status: String) {
        label.stringValue = status
        layoutLabel()
    }

    /// Stops blocking. The cursor lingers briefly, then fades.
    func end() {
        isBlocking = false
        labelBackground.isHidden = true
        let work = DispatchWorkItem { [weak self] in self?.setCursorVisible(false) }
        hideCursorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Cursor

    /// Glides the cursor tip to `point` with an ease-in-out curve.
    func moveCursor(to point: NSPoint, duration: TimeInterval) async {
        let from = cursorPoint ?? NSPoint(x: bounds.midX, y: bounds.midY)
        cursorPoint = point
        guard duration > 0 else {
            placeCursor(at: point)
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setCompletionBlock { continuation.resume() }
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: from)
            animation.toValue = NSValue(point: point)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            CATransaction.setDisableActions(true)
            cursorLayer.position = point
            cursorLayer.add(animation, forKey: "move")
            CATransaction.commit()
        }
    }

    /// An expanding ring at the cursor tip, for a click.
    func ripple() {
        guard let point = cursorPoint else { return }
        let ring = CAShapeLayer()
        let size: CGFloat = 34
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.position = point
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor = Colors.accentPrimary.withAlphaComponent(0.25).cgColor
        ring.strokeColor = Colors.accentPrimary.cgColor
        ring.lineWidth = 2
        ring.zPosition = 9
        layer?.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.2
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.opacity = 0
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    private func placeCursor(at point: NSPoint) {
        cursorPoint = point
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = point
        CATransaction.commit()
    }

    private func setCursorVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        cursorLayer.opacity = visible ? 1 : 0
        CATransaction.commit()
    }

    // MARK: - Layout & drawing

    override func layout() {
        super.layout()
        layoutLabel()
    }

    private func layoutLabel() {
        label.sizeToFit()
        let width = min(label.frame.width + 24, bounds.width - 24)
        let height: CGFloat = 22
        labelBackground.frame = NSRect(x: bounds.midX - width / 2, y: bounds.maxY - height - 14, width: width, height: height)
        label.frame = NSRect(x: 12, y: (height - label.frame.height) / 2, width: width - 24, height: label.frame.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cursorLayer.fillColor = Colors.accentPrimary.cgColor
            cursorLayer.strokeColor = Colors.surfacePrimary.cgColor
        }
        label.textColor = Colors.foregroundPrimary
    }

    /// A classic pointer arrow with its tip at (0, 0), y pointing down.
    private static func arrowPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 17))
        path.addLine(to: CGPoint(x: 4.2, y: 13.2))
        path.addLine(to: CGPoint(x: 7.2, y: 20))
        path.addLine(to: CGPoint(x: 10, y: 18.8))
        path.addLine(to: CGPoint(x: 7.1, y: 12.2))
        path.addLine(to: CGPoint(x: 12.6, y: 12.2))
        path.closeSubpath()
        return path
    }
}
