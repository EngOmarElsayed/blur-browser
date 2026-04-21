import AppKit
import WebKit

/// Coordinates WKDownload lifecycle: confirms with the user, decides the destination
/// in ~/Downloads/, tracks progress via KVO, and forwards state to DownloadStore.
@MainActor
final class DownloadManager: NSObject {

    private let store: DownloadStore
    weak var webViewController: WebViewController?

    /// Active WKDownload tracking keyed by our UUID.
    private var activeDownloads: [UUID: ActiveDownload] = [:]

    /// Reverse lookup from WKDownload to our UUID so delegate callbacks can find state.
    private var downloadIDs: [ObjectIdentifier: UUID] = [:]

    init(store: DownloadStore) {
        self.store = store
        super.init()
    }

    // MARK: - Public API

    /// Attach the manager as delegate of a new WKDownload. Shows the confirmation
    /// alert; if allowed, the download proceeds. Otherwise it's cancelled.
    func beginDownload(
        _ download: WKDownload,
        sourceURL: URL?,
        expectedSize: Int64?
    ) {
        download.delegate = self
        let active = ActiveDownload(
            id: UUID(),
            sourceURL: sourceURL,
            expectedSize: expectedSize,
            download: download
        )
        activeDownloads[active.id] = active
        downloadIDs[ObjectIdentifier(download)] = active.id
    }

    /// Cancel an in-progress download by id (called from the toast X button).
    func cancelDownload(id: UUID) {
        if let active = activeDownloads[id] {
            cancelActiveDownloads(active: active)
        } else {
            guard let item = store.items.first(where: { $0.id == id }) else { return }
            cancelPausedDownloads(pausedItem: item)
        }
    }

    private func cancelPausedDownloads(pausedItem: DownloadItem) {
        // Remove partial file if it exists
        if let url = URL(string: pausedItem.localURL) {
            try? FileManager.default.removeItem(at: url)
        }

        self.store.markCancelled(id: pausedItem.id)
        self.cleanup(id: pausedItem.id)
    }

    private func cancelActiveDownloads(active: ActiveDownload) {
        active.download.cancel { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Remove partial file if it exists
                if let localURL = active.localURL {
                    try? FileManager.default.removeItem(at: localURL)
                }

                self.store.markCancelled(id: active.id)
                self.cleanup(id: active.id)
            }
        }
    }

    /// Cancel all active downloads — used on app quit.
    func cancelAll() {
        for (id, _) in activeDownloads {
            cancelDownload(id: id)
        }
    }

    /// Pause an in-progress download. WKDownload doesn't expose a real pause —
    /// we cancel with resume data and mark the item as paused, then resume
    /// later via `WKWebView.resumeDownload(fromResumeData:)`.
    func pauseDownload(id: UUID) {
        guard let active = activeDownloads[id] else { return }
        active.download.cancel { [weak self] resumeData in
            guard let self else { return }
            Task { @MainActor in
                active.observation?.invalidate()
                active.observation = nil
                self.store.markPaused(id: id, resumeData: resumeData)
                // Keep the entry in activeDownloads so `resumeDownload(id:)`
                // can find the existing metadata — but detach from WKDownload.
                self.activeDownloads.removeValue(forKey: id)
                self.downloadIDs.removeValue(forKey: ObjectIdentifier(active.download))
            }
        }
    }

    /// Resume a previously paused download on the given web view.
    func resumeDownload(id: UUID, using webView: WKWebView) {
        guard let item = store.items.first(where: { $0.id == id }),
              let resumeData = item.resumeData else { return }

        webView.resumeDownload(fromResumeData: resumeData) { [weak self] download in
            guard let self else { return }
            Task { @MainActor in
                download.delegate = self
                let active = ActiveDownload(
                    id: id,
                    sourceURL: item.sourceFileURL,
                    expectedSize: item.totalBytes,
                    download: download
                )
                active.localURL = item.localFileURL
                active.observation = download.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
                    guard let self else { return }
                    let completed = Int64(progress.completedUnitCount)
                    let total: Int64? = progress.totalUnitCount > 0 ? Int64(progress.totalUnitCount) : nil
                    Task { @MainActor in
                        self.store.updateProgress(id: id, completed: completed, total: total)
                    }
                }
                self.activeDownloads[id] = active
                self.downloadIDs[ObjectIdentifier(download)] = id
                self.store.markResumed(id: id)
            }
        }
    }

    // MARK: - Private

    private func cleanup(id: UUID) {
        if let active = activeDownloads.removeValue(forKey: id) {
            active.observation?.invalidate()
            downloadIDs.removeValue(forKey: ObjectIdentifier(active.download))
        }
    }

    private func id(for download: WKDownload) -> UUID? {
        downloadIDs[ObjectIdentifier(download)]
    }

    private struct ActiveDownloadState {
        var localURL: URL?
        var observation: NSKeyValueObservation?
    }

    /// In-flight download metadata.
    private final class ActiveDownload {
        let id: UUID
        let sourceURL: URL?
        let expectedSize: Int64?
        let download: WKDownload
        var localURL: URL?
        var observation: NSKeyValueObservation?

        init(id: UUID, sourceURL: URL?, expectedSize: Int64?, download: WKDownload) {
            self.id = id
            self.sourceURL = sourceURL
            self.expectedSize = expectedSize
            self.download = download
        }
    }
}

// MARK: - WKDownloadDelegate

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard let id = id(for: download),
              let active = activeDownloads[id] else {
            completionHandler(nil)
            return
        }

        // Use actual expected content length if we didn't know it earlier
        let size: Int64? = {
            if let s = active.expectedSize, s > 0 { return s }
            if response.expectedContentLength > 0 { return response.expectedContentLength }
            return nil
        }()

        let host = active.sourceURL?.host ?? response.url?.host

        guard let vc = webViewController else {
            completionHandler(nil)
            cleanup(id: id)
            return
        }

        vc.showDownloadConfirmation(
            filename: suggestedFilename,
            host: host,
            expectedSize: size
        ) { [weak self] allowed in
            guard let self else {
                completionHandler(nil)
                return
            }

            // The navigation that triggered this download set the tab's URL
            // optimistically to the download URL. Now that the user has made a
            // decision (allow or deny), force the address bar back to the
            // web view's last committed URL so it doesn't keep showing the
            // download URL.
            if let webView = download.webView,
               let tab = self.webViewController?.tabForWebView(webView) {
                tab.url = webView.url
            }

            guard allowed else {
                completionHandler(nil)
                download.cancel(nil)
                self.cleanup(id: id)
                return
            }

            // Resolve destination in ~/Downloads/ with collision handling
            let destURL = Self.uniqueDownloadURL(suggestedFilename: suggestedFilename)
            active.localURL = destURL

            // Create store record now that the user has allowed
            self.store.addDownload(
                id: id,
                fileName: destURL.lastPathComponent,
                localURL: destURL,
                sourceURL: active.sourceURL ?? response.url,
                totalBytes: size
            )

            // Observe progress and forward to the store
            active.observation = download.progress.observe(\.completedUnitCount) { [weak self, weak active] progress, _ in
                guard let self, let active else { return }
                let completed = Int64(progress.completedUnitCount)
                let total: Int64? = progress.totalUnitCount > 0 ? Int64(progress.totalUnitCount) : nil
                Task { @MainActor in
                    self.store.updateProgress(id: active.id, completed: completed, total: total)
                }
            }

            completionHandler(destURL)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = id(for: download) else { return }
        store.markCompleted(id: id)
        cleanup(id: id)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = id(for: download) else { return }
        store.markFailed(id: id)
        cleanup(id: id)
    }

    // MARK: - Filename Collision Handling

    private static func uniqueDownloadURL(suggestedFilename: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var candidate = downloads.appendingPathComponent(suggestedFilename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty
                ? "\(stem) (\(index))"
                : "\(stem) (\(index)).\(ext)"
            candidate = downloads.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }
}
