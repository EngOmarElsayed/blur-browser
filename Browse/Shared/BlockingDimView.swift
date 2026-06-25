//
//  BlockingDimView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import AppKit

/// An NSView that intercepts ALL mouse events so nothing passes through to views underneath.
final class BlockingDimView: NSView {
    var onClickOutside: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { onClickOutside?() }
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) { onClickOutside?() }
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) { onClickOutside?() }
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func cursorUpdate(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func mouseEntered(with event: NSEvent) {}
    override func mouseExited(with event: NSEvent) {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(convert(point, from: superview)) {
            return self
        }
        return nil
    }
}
