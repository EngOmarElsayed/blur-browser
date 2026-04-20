import AppKit

/// NSView that applies a Gaussian blur to whatever is rendered behind it,
/// with a tunable radius.
///
/// Uses the private `CAFilter` class (via runtime lookup) to set a
/// `gaussianBlur` filter on the layer's `backgroundFilters`. `CAFilter` is
/// private API — App Store static analysis may flag it. Safe for direct
/// distribution, Developer ID notarization, and internal builds.
@MainActor
final class GaussianBlurView: NSView {

    /// Blur radius in points. Setting this updates the filter in-place.
    var blurRadius: CGFloat {
        didSet { applyBlur() }
    }

    init(radius: CGFloat) {
        self.blurRadius = radius
        super.init(frame: .zero)
        wantsLayer = true
        // The view itself must be transparent; only the blur filter contributes.
        layer?.backgroundColor = NSColor.clear.cgColor
        applyBlur()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyBlur() {
        guard let layer else { return }

        // Look up the private `CAFilter` class at runtime.
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol else {
            return
        }

        // CAFilter.filterWithType("gaussianBlur")
        let typedSelector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: typedSelector) else { return }
        let filterUnmanaged = filterClass.perform(typedSelector, with: "gaussianBlur")
        guard let filter = filterUnmanaged?.takeUnretainedValue() as? NSObject else { return }

        // Set the input radius via KVC
        filter.setValue(blurRadius, forKey: "inputRadius")

        layer.backgroundFilters = [filter]
    }
}
