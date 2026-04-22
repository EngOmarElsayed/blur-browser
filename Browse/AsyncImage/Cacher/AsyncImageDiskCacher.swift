//
//  AsyncImageDiskCacher.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 22/04/2026.
//

import Foundation
import CryptoKit

/// A singleton cache manager that persists image data on disk across application launches.
///
/// `AsyncImageDiskCacher` mirrors the API of ``AsyncImageAppSessionCacher`` but stores
/// image bytes as files in the user's Caches directory. Each entry's filename is the
/// SHA-256 hash of the source URL, so arbitrary URLs map to safe filenames.
///
/// This class implements the Singleton pattern through the `shared` static property and
/// cannot be directly initialized.
///
/// ## Topics
/// ### Accessing the Cache
/// - ``shared``
///
/// ### Managing Cached Images
/// - ``fetchImageForURL(_:)``
/// - ``cacheImage(_:forURL:)``
/// - ``removeCachedImage(forURL:)``
/// - ``removeAllCachedImages()``
///
/// ## See Also
/// - ``AsyncImage``
/// - ``AsyncImageAppSessionCacher``
/// - ``CachingPolicy``
final public class AsyncImageDiskCacher: @unchecked Sendable {
    /// The shared instance of the disk cacher.
    ///
    /// Use this property to access the singleton instance. The cache is shared across
    /// the entire application and persists across launches until explicitly cleared
    /// or evicted by the system under disk pressure.
    public static let shared = AsyncImageDiskCacher()

    /// Absolute directory where cached image files are stored.
    ///
    /// Located under `NSCachesDirectory/AsyncImageCache/`. The system may reclaim files
    /// under this directory when disk pressure is high — appropriate behavior for image
    /// caches since re-downloading is always possible.
    private let directory: URL

    /// Queue that serializes file I/O. Reads use `.sync` on a concurrent queue,
    /// writes use `.async(flags: .barrier)` for exclusive access. Keeps the cacher
    /// thread-safe without blocking callers on the main actor.
    private let queue = DispatchQueue(
        label: "AsyncImageDiskCacher.io",
        qos: .utility,
        attributes: .concurrent
    )

    /// Private initializer to enforce singleton pattern.
    private init() {
        let baseDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
        directory = baseDir.appendingPathComponent("AsyncImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// Retrieves cached image data for the specified URL from disk.
    ///
    /// - Parameter url: The URL for which to retrieve cached image data.
    /// - Returns: The cached image data if a file exists for the URL, otherwise `nil`.
    ///
    /// ## Example
    /// ```swift
    /// if let cachedData = AsyncImageDiskCacher.shared.fetchImageForURL(url) {
    ///     // Use the cached image
    /// }
    /// ```
    public func fetchImageForURL(_ url: URL) -> Data? {
        let fileURL = fileURL(for: url)
        return queue.sync {
            try? Data(contentsOf: fileURL)
        }
    }

    /// Stores image data in the disk cache for the specified URL.
    ///
    /// The data is written atomically to a file under the cache directory. Writes are
    /// dispatched off the caller's queue so this method returns immediately.
    ///
    /// - Parameters:
    ///   - imageData: The image data to cache.
    ///   - url: The URL to associate with the cached image data.
    ///
    /// ## Example
    /// ```swift
    /// AsyncImageDiskCacher.shared.cacheImage(data, forURL: imageURL)
    /// ```
    public func cacheImage(_ imageData: Data, forURL url: URL) {
        let fileURL = fileURL(for: url)
        queue.async(flags: .barrier) {
            try? imageData.write(to: fileURL, options: .atomic)
        }
    }

    /// Removes cached image data for the specified URL.
    ///
    /// - Parameter url: The URL for which to remove cached image data.
    ///
    /// ## Example
    /// ```swift
    /// AsyncImageDiskCacher.shared.removeCachedImage(forURL: imageURL)
    /// ```
    public func removeCachedImage(forURL url: URL) {
        let fileURL = fileURL(for: url)
        queue.async(flags: .barrier) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Removes all cached image data.
    ///
    /// Deletes the entire cache directory and re-creates it empty. Use this when you
    /// need to free disk space or reset the cache state.
    ///
    /// ## Example
    /// ```swift
    /// AsyncImageDiskCacher.shared.removeAllCachedImages()
    /// ```
    public func removeAllCachedImages() {
        queue.async(flags: .barrier) { [directory] in
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Private Helpers

    /// Resolves a URL to its on-disk cache file path.
    ///
    /// Uses SHA-256 to produce a filesystem-safe filename — arbitrary URLs may contain
    /// characters (/, ?, #, etc.) that aren't valid in filenames, and direct URL
    /// encoding can exceed the filesystem's filename length limit.
    private func fileURL(for url: URL) -> URL {
        let key = url.absoluteString
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename)
    }
}
