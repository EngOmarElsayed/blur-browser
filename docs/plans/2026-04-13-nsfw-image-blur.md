# NSFW Image Blur Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Hide all images on web pages until a CoreML classifier confirms they are safe; blur NSFW images permanently.

**Architecture:** JavaScript injected via WKUserScript observes the DOM for `<img>` elements, hides them immediately, sends their URLs to Swift through a WKScriptMessageHandler. Swift downloads the image, runs the bundled NSFWClassifier CoreML model (224x224 RGB MobileNetV2, 5 classes), and calls back into JS to either reveal (safe) or blur (nsfw) the image.

**Tech Stack:** Swift 5.10, CoreML, WKWebView (WKUserScript + WKScriptMessageHandler), JavaScript (MutationObserver), macOS 14.0+

---

### Task 1: Create NSFWClassifierService

The CoreML wrapper that loads the model and classifies images.

**Files:**
- Create: `Browse/WebContent/NSFWClassifierService.swift`

**Step 1: Create the classifier service**

```swift
import CoreML
import AppKit
import CoreGraphics
import CoreImage

actor NSFWClassifierService {
    static let shared = NSFWClassifierService()

    private var model: NSFWClassifier?
    private var cache: [String: Bool] = [:]

    private let nsfwThreshold: Double = 0.6

    private func loadModel() throws -> NSFWClassifier {
        if let model { return model }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let loaded = try NSFWClassifier(configuration: config)
        self.model = loaded
        return loaded
    }

    func classify(imageData: Data, url: String) async -> Bool {
        if let cached = cache[url] { return cached }

        guard let cgImage = cgImage(from: imageData) else { return false }

        do {
            let model = try loadModel()
            let resized = resize(cgImage, to: CGSize(width: 224, height: 224))
            let pixelBuffer = try pixelBuffer(from: resized)
            let input = try NSFWClassifierInput(inputWith: pixelBuffer)
            let output = try model.prediction(input: input)
            let probs = output.classLabel_probs

            let nsfwScore = (probs["Porn"] ?? 0)
                + (probs["Hentai"] ?? 0)
                + (probs["Sexy"] ?? 0)

            let isNSFW = nsfwScore > nsfwThreshold
            cache[url] = isNSFW
            return isNSFW
        } catch {
            return false // fail open — don't block broken images
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Image Helpers

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func resize(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }

    private func pixelBuffer(from cgImage: CGImage) throws -> CVPixelBuffer {
        let width = cgImage.width
        let height = cgImage.height
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "NSFWClassifier", code: -1)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (the auto-generated NSFWClassifier class from the .mlpackage should be available)

**Step 3: Commit**

```bash
git add Browse/WebContent/NSFWClassifierService.swift
git commit -m "feat: add NSFWClassifierService CoreML wrapper"
```

---

### Task 2: Create the JavaScript content filter script

The DOM observation script that hides images and communicates with Swift.

**Files:**
- Create: `Browse/Resources/content-filter.js`

**Step 1: Write the content filter JavaScript**

```javascript
(function() {
    'use strict';

    const MIN_SIZE = 50;
    const processedMap = new Map();
    let idCounter = 0;

    // Inject styles
    const style = document.createElement('style');
    style.id = 'nsfw-filter-styles';
    style.textContent = `
        .nsfw-hidden {
            opacity: 0 !important;
            transition: none !important;
        }
        .nsfw-safe {
            opacity: 1 !important;
            transition: opacity 0.15s ease !important;
        }
        .nsfw-blur {
            filter: blur(25px) grayscale(100%) !important;
            opacity: 1 !important;
            transition: opacity 0.15s ease !important;
        }
    `;
    (document.head || document.documentElement).appendChild(style);

    // Callback from Swift
    window.__nsfwCallback = function(id, verdict) {
        const el = processedMap.get(id);
        if (!el) return;
        el.classList.remove('nsfw-hidden');
        if (verdict === 'nsfw') {
            el.classList.add('nsfw-blur');
        } else {
            el.classList.add('nsfw-safe');
        }
        el.setAttribute('data-nsfw-status', verdict);
    };

    function shouldProcess(img) {
        if (img.hasAttribute('data-nsfw-id')) return false;
        const src = img.currentSrc || img.src;
        if (!src || src.startsWith('data:image/svg') || src.startsWith('data:image/gif')) return false;
        return true;
    }

    function isTooSmall(img) {
        const w = img.naturalWidth || img.width || img.offsetWidth;
        const h = img.naturalHeight || img.height || img.offsetHeight;
        return (w > 0 && w < MIN_SIZE) || (h > 0 && h < MIN_SIZE);
    }

    function processImage(img) {
        if (!shouldProcess(img)) return;

        const nsfwId = 'nsfw-' + (++idCounter);
        img.setAttribute('data-nsfw-id', nsfwId);

        // If we can already tell it's tiny, skip
        if (isTooSmall(img)) {
            img.setAttribute('data-nsfw-status', 'safe');
            img.classList.add('nsfw-safe');
            return;
        }

        // Hide until classified
        img.classList.add('nsfw-hidden');
        img.setAttribute('data-nsfw-status', 'pending');
        processedMap.set(nsfwId, img);

        const src = img.currentSrc || img.src;
        try {
            const absoluteURL = new URL(src, document.baseURI).href;
            window.webkit.messageHandlers.nsfwFilter.postMessage({
                id: nsfwId,
                src: absoluteURL
            });
        } catch(e) {
            // If URL parsing fails, show the image
            img.classList.remove('nsfw-hidden');
            img.classList.add('nsfw-safe');
            img.setAttribute('data-nsfw-status', 'safe');
        }
    }

    function processLoadedImage(img) {
        if (img.hasAttribute('data-nsfw-id') && img.getAttribute('data-nsfw-status') === 'pending') return;
        if (img.hasAttribute('data-nsfw-id')) return;

        // Re-check size now that it's loaded
        if (isTooSmall(img)) {
            img.setAttribute('data-nsfw-id', 'nsfw-' + (++idCounter));
            img.setAttribute('data-nsfw-status', 'safe');
            img.classList.add('nsfw-safe');
            return;
        }
        processImage(img);
    }

    function scanExistingImages() {
        document.querySelectorAll('img').forEach(function(img) {
            if (img.complete && img.naturalWidth > 0) {
                processLoadedImage(img);
            } else {
                processImage(img);
                img.addEventListener('load', function() {
                    // If already pending and too small, reveal it
                    if (isTooSmall(img) && img.getAttribute('data-nsfw-status') === 'pending') {
                        img.classList.remove('nsfw-hidden');
                        img.classList.add('nsfw-safe');
                        img.setAttribute('data-nsfw-status', 'safe');
                    }
                }, { once: true });
            }
        });
    }

    // Observe DOM for new images
    const observer = new MutationObserver(function(mutations) {
        for (const mutation of mutations) {
            for (const node of mutation.addedNodes) {
                if (node.nodeType !== 1) continue;
                if (node.tagName === 'IMG') {
                    processImage(node);
                } else if (node.querySelectorAll) {
                    node.querySelectorAll('img').forEach(processImage);
                }
            }
        }
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true
    });

    // Scan on DOMContentLoaded and immediately
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scanExistingImages);
    } else {
        scanExistingImages();
    }
})();
```

**Step 2: Commit**

```bash
git add Browse/Resources/content-filter.js
git commit -m "feat: add content-filter.js for DOM image observation"
```

---

### Task 3: Create ContentFilterMessageHandler

The Swift bridge between JS and the classifier.

**Files:**
- Create: `Browse/WebContent/ContentFilterMessageHandler.swift`

**Step 1: Write the message handler**

```swift
import WebKit

@MainActor
final class ContentFilterMessageHandler: NSObject, WKScriptMessageHandler {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: String],
              let id = body["id"],
              let src = body["src"],
              let url = URL(string: src) else { return }

        let webView = message.webView

        Task { [weak webView] in
            let verdict = await classify(url: url, src: src)
            guard let webView else { return }
            let js = "window.__nsfwCallback('\(id)', '\(verdict)')"
            try? await webView.evaluateJavaScript(js)
        }
    }

    private func classify(url: URL, src: String) async -> String {
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return "safe"
            }

            // Skip tiny downloads (likely tracking pixels)
            guard data.count > 1024 else { return "safe" }

            let isNSFW = await NSFWClassifierService.shared.classify(
                imageData: data,
                url: src
            )
            return isNSFW ? "nsfw" : "safe"
        } catch {
            return "safe" // fail open
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Browse/WebContent/ContentFilterMessageHandler.swift
git commit -m "feat: add ContentFilterMessageHandler bridging JS to CoreML"
```

---

### Task 4: Wire everything into WebViewConfiguration

Connect the JS script and message handler to every WKWebView.

**Files:**
- Modify: `Browse/WebContent/WebViewConfiguration.swift` (full rewrite, 13 lines → ~35 lines)

**Step 1: Update WebViewConfiguration.swift**

Replace the entire file contents with:

```swift
import WebKit

enum WebViewConfiguration {

    private static let contentFilterHandler = ContentFilterMessageHandler()

    @MainActor
    static func makeDefault() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.isElementFullscreenEnabled = true

        let contentController = WKUserContentController()

        // Load and inject the content filter script
        if let scriptURL = Bundle.main.url(forResource: "content-filter", withExtension: "js"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let userScript = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            contentController.addUserScript(userScript)
        }

        // Register the message handler for NSFW classification
        contentController.add(contentFilterHandler, name: "nsfwFilter")

        config.userContentController = contentController

        return config
    }
}
```

**Important note:** The `contentFilterHandler` is stored as a static property to prevent it from being deallocated. `WKUserContentController.add(_:name:)` does NOT retain the handler on macOS with `ENABLE_USER_SCRIPT_SANDBOXING = YES`. Keeping it static ensures it lives for the app's lifetime.

**Step 2: Verify it compiles and runs**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Browse/WebContent/WebViewConfiguration.swift
git commit -m "feat: wire content filter script and handler into WKWebView config"
```

---

### Task 5: Update project.yml to bundle the JS file

The JS file is in Resources/ but the xcodegen config excludes the Resources directory from sources. It only includes specific resource files. We need to add content-filter.js.

**Files:**
- Modify: `Browse/project.yml` (add 1 resource entry)

**Step 1: Add JS resource to project.yml**

Add this line to the `resources:` array (after the Assets.xcassets entry):

```yaml
      - path: Browse/Resources/content-filter.js
```

So the resources section becomes:

```yaml
    resources:
      - path: Browse/Resources/Assets.xcassets
      - path: Browse/Resources/content-filter.js
      - path: Browse/Resources/Info.plist
        buildPhase: none
```

**Step 2: Regenerate Xcode project and restore entitlements**

Run:
```bash
cd /Users/omarelsayed/Documents/Browse
xcodegen generate
```

Then immediately verify/restore Browse.entitlements (xcodegen overwrites it):

```bash
cat Browse/Resources/Browse.entitlements
```

If the `com.apple.security.network.client` key is missing, restore it:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Step 3: Full build verification**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add project.yml Browse/Resources/content-filter.js
git commit -m "feat: bundle content-filter.js as app resource"
```

---

### Task 6: End-to-end verification

Manually verify the full pipeline works.

**Step 1: Build and run**

```bash
xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build
```

Open the app, navigate to any image-heavy page (e.g., google images search). Verify:

1. Images briefly hidden (opacity 0) on page load
2. Safe images fade in after ~0.1-0.5s (classification time)
3. No console errors in Xcode logs related to NSFW or content filter
4. App doesn't crash or freeze

**Step 2: Commit all remaining changes**

```bash
git add -A
git commit -m "feat: NSFW image blur — end-to-end integration complete"
```
