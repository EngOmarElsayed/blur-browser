//
//  CachingPolicy.swift
//  AsyncImageApp
//
//  Created by Omar Elsayed on 21/04/2025.
//

import Foundation

/// A policy that determines how long downloaded images should remain cached.
///
/// `CachingPolicy` provides two strategies for managing image caching duration:
/// - `.withViewCycle`: Images are cached only for the lifetime of the view that requested them
/// - `.duringAppSession`: Images remain cached for the entire application session
///
/// Choose an appropriate policy based on the specific memory and performance requirements of your application.
///
/// ## Topics
/// ### Creating a Caching Policy
/// - ``withViewCycle``
/// - ``duringAppSession``
///
/// ## See Also
/// - ``AsyncImage``
public enum CachingPolicy: Sendable {
    /// Cache images only for the lifetime of the ``AsyncImage`` view.
    ///
    /// When using this policy, images are automatically released from memory when the
    /// ``AsyncImage`` view instance is deallocated.
    ///
    ///- Warning: Avoid using `.withViewCycle` in `LazyStack` views as it may cause
    ///   repeated image loading during scrolling, which can negatively impact performance
    ///   and user experience use `.duringAppSession` instead.
    ///
    case withViewCycle

    /// Cache images for the entire application session.
    ///
    /// When using this policy, images remain in memory until the application is terminated
    /// or the cache is explicitly cleared. This improves performance when the same images
    /// are displayed multiple times.
    ///
    /// - Note: This policy uses `NSCache` to cache fetched image data which is thread safe and it contains
    ///  various auto-eviction policies, which ensure that a cache doesn’t use too much of the system’s memory.
    ///  If memory is needed by other applications, these policies remove some items from the cache, minimizing its memory footprint.
    ///
    case duringAppSession

    /// Cache images on disk so they persist across application launches.
    ///
    /// Images are stored as files under the user's Caches directory, keyed by a SHA-256
    /// hash of the URL. Reads go through a memory hot-layer first, so repeated reads
    /// within a session don't touch disk. On cache miss, the image is downloaded, then
    /// written to both memory and disk.
    ///
    /// - Note: The system may reclaim the Caches directory under disk pressure — this
    ///   is appropriate behavior for image data and matches what Apple's own cached
    ///   network images do.
    ///
    case onDisk
}
