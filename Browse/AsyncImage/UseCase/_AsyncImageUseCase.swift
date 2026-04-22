//
//  AsyncImageUseCase.swift
//  AsyncImage
//
//  Created by Omar Elsayed on 22/04/2025.
//

import SwiftUI

struct _AsyncImageUseCase: Sendable {
    private let imageFetcher: _AsyncImageFetcher = .init()
    private let imageAppSessionCacher: AsyncImageAppSessionCacher = .shared
    private let imageDiskCacher: AsyncImageDiskCacher = .shared
}

// MARK: - Fetch Method
extension _AsyncImageUseCase {
    func fetchImage(url: URL?, for cachingPolicy: CachingPolicy) async throws -> Image {
        guard let url = url else { throw AsyncImageError.invilaedUrl(url) }
        if let cachedImageData = checkCachedImageData(for: url, policy: cachingPolicy),
           cachingPolicy != .withViewCycle {
            guard let image = Image(data: cachedImageData) else { throw AsyncImageError.invalidData(cachedImageData) }

            return image
        } else {
            let finalImageData = try await getImageFrom(from: url)
            guard let finalImage = Image(data: finalImageData) else { throw AsyncImageError.invalidData(finalImageData) }
            cacheImage(for: cachingPolicy, finalImageData, url)

            return finalImage
        }
    }
}

// MARK: - Private Methods
extension _AsyncImageUseCase {
    private func getImageFrom(from url: URL?) async throws -> Data {
        return try await imageFetcher.fetchImage(at: url)
    }

    /// Look up the URL in the appropriate cache layer(s) for the given policy.
    /// - `.duringAppSession`: memory only.
    /// - `.onDisk`: memory first (hot), then disk. A disk hit promotes the bytes
    ///   back into memory so subsequent reads in this session don't touch disk.
    /// - `.withViewCycle`: no cache lookup.
    private func checkCachedImageData(for url: URL, policy: CachingPolicy) -> Data? {
        switch policy {
        case .withViewCycle:
            return nil
        case .duringAppSession:
            return imageAppSessionCacher.fetchImageForURL(url)
        case .onDisk:
            if let memHit = imageAppSessionCacher.fetchImageForURL(url) {
                return memHit
            }
            if let diskHit = imageDiskCacher.fetchImageForURL(url) {
                // Promote to memory so repeat reads stay hot.
                imageAppSessionCacher.cacheImage(diskHit, forURL: url)
                return diskHit
            }
            return nil
        }
    }

    private func cacheImage(for cachingPolicy: CachingPolicy, _ image: Data, _ url: URL?) {
        guard let url else { return }
        switch cachingPolicy {
        case .duringAppSession:
            imageAppSessionCacher.cacheImage(image, forURL: url)
        case .onDisk:
            // Write-through: keep in memory for fast re-reads AND persist to disk
            // so subsequent app launches serve from disk without hitting the network.
            imageAppSessionCacher.cacheImage(image, forURL: url)
            imageDiskCacher.cacheImage(image, forURL: url)
        case .withViewCycle:
            break
        }
    }
}
