import AppKit

/// A layer-backed NSView that renders a wallpaper image with aspect-fill
/// scaling (same semantics as CSS `object-fit: cover`).
///
/// Used as an overlay on top of a tab's WKWebView whenever that tab is
/// "the new tab page" (its URL equals `AppConstants.newTabURL`). Rendering
/// natively avoids the ~100–500ms WKWebView cold-start + HTML parse that the
/// old `blur://newtab` path incurred — the wallpaper appears as soon as
/// AppKit runs the next layout pass.
@MainActor
final class NewTabWallpaperView: NSView {

    // MARK: - Image cache

    /// NSImage instances keyed by wallpaper filename. Image data stays in
    /// memory once loaded, so switching back to a tab that already displayed
    /// a given wallpaper is a single dictionary lookup — no disk I/O.
    private static var imageCache: [String: NSImage] = [:]

    private static func image(named wallpaper: String) -> NSImage? {
        if let cached = imageCache[wallpaper] { return cached }
        guard let url = Bundle.main.url(forResource: wallpaper, withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache[wallpaper] = image
        return image
    }

    // MARK: - View

    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Chrome color shows at launch or if the image fails to load.
        layer?.backgroundColor = Colors.chromeBg.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Sets the displayed wallpaper. Pass nil to show only the chrome color.
    func setWallpaper(named filename: String?) {
        guard let filename, let image = Self.image(named: filename) else {
            imageLayer.contents = nil
            return
        }
        imageLayer.contents = image
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    // Re-read chrome color on theme change (reapplyTheme() → setNeedsDisplay).
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = Colors.chromeBg.cgColor
    }
}
