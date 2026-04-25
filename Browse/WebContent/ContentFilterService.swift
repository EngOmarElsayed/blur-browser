import AppKit
import CoreML
import Vision

/// Centralized NSFW classification service using the CoreML NSFWClassifier model.
/// Shared across all tabs — one model instance, used from any `WebViewCoordinator`.
@MainActor
final class ContentFilterService {

    static let shared = ContentFilterService()

    private var nsfwModel: VNCoreMLModel?
    private let nsfwCategories: Set<String> = ["porn", "hentai", "sexy"]

    struct Prediction: Sendable {
        let label: String
        let confidence: Float
    }

    private init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try NSFWClassifier(configuration: config)
            self.nsfwModel = try VNCoreMLModel(for: model.model)
            print("[ContentFilter] ✅ NSFW model loaded")
        } catch {
            print("[ContentFilter] ❌ NSFW model failed: \(error)")
            self.nsfwModel = nil
        }
    }

    var isModelLoaded: Bool { nsfwModel != nil }

    /// Classify an image and return all predictions sorted by confidence.
    func classifyImage(_ cgImage: CGImage) async -> [Prediction]? {
        guard let model = nsfwModel else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNClassificationObservation],
                      !results.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let predictions = results.map {
                    Prediction(label: $0.identifier, confidence: $0.confidence)
                }
                continuation.resume(returning: predictions)
            }
            // Inception v3 was trained on center-cropped ImageNet images.
            // `.scaleFill` stretches non-square inputs, pushing them out of
            // the training distribution and hurting accuracy. Center-crop
            // matches the model's expected input geometry.
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[ContentFilter] Vision error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// NSFW if any of porn/hentai/sexy >= 0.5, OR neutral < 0.5
    func isNSFW(_ results: [Prediction]) -> Bool {
        for result in results where nsfwCategories.contains(result.label) {
            if result.confidence >= 0.5 {
                return true
            }
        }

        let neutralConfidence = results.first(where: { $0.label == "neutral" })?.confidence ?? 0
        let drawingsConfidence = results.first(where: { $0.label == "drawings" })?.confidence ?? 0

        let pornConfidence = results.first(where: { $0.label == "porn" })?.confidence ?? 0
        let hentaiConfidence = results.first(where: { $0.label == "hentai" })?.confidence ?? 0
        let sexyConfidence = results.first(where: { $0.label == "sexy" })?.confidence ?? 0
//        let compaination = pornConfidence + sexyConfidence + hentaiConfidence

        return (neutralConfidence < 0.5 && drawingsConfidence < 0.5) && (pornConfidence >= 0.5 || hentaiConfidence >= 0.5 || sexyConfidence >= 0.5)
    }

    /// Format all results into a readable string for logging.
    func formatResults(_ results: [Prediction]) -> String {
        results.map { "\($0.label): \(String(format: "%.1f%%", $0.confidence * 100))" }
            .joined(separator: " | ")
    }

    /// Decode a base64 JPEG data URL into a CGImage.
    func decodeCGImage(from dataURL: String) -> CGImage? {
        guard let b64 = dataURL.components(separatedBy: ",").last,
              let data = Data(base64Encoded: b64),
              let nsImage = NSImage(data: data),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return cg
    }

    /// Download an image via URLSession (no CORS restrictions), resize to max 300px.
    func fetchImageNatively(src: String) async -> CGImage? {
        guard let url = URL(string: src) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                  contentType.hasPrefix("image/")
            else { return nil }

            guard let nsImage = NSImage(data: data),
                  let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }

            let maxDim: CGFloat = 300
            let w = CGFloat(cg.width)
            let h = CGFloat(cg.height)
            guard w >= 80, h >= 80 else { return nil }
            if w <= maxDim && h <= maxDim { return cg }

            let scale = min(maxDim / w, maxDim / h)
            let newW = Int(w * scale)
            let newH = Int(h * scale)

            guard let context = CGContext(
                data: nil, width: newW, height: newH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return cg }

            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
            return context.makeImage() ?? cg
        } catch {
            return nil
        }
    }
}
