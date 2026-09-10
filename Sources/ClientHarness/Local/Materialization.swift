// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Brings the content of a File Provider item onto disk, and removes it again.
///
/// The obvious API for this, `NSFileProviderManager`, is reserved for the provider's own app and its sibling extensions, so a test process cannot use it against the client's domain. What remains are the file system routes: reading a file is what the system turns into a fetch, and the ubiquitous item calls on `FileManager` may or may not apply to a replicated domain — which is what spike S3 establishes.
///
public enum Materialization {
    ///
    /// Fetch the content of an item by reading it.
    ///
    /// - Parameters:
    ///     - url: The item to materialize.
    ///
    /// - Returns: The content which arrived.
    ///
    /// - Throws: Whatever reading the file raises, including the error the extension reports when a fetch fails.
    ///
    @discardableResult
    public static func materialize(_ url: URL) throws -> Data {
        try Data(contentsOf: url, options: [.uncached])
    }

    ///
    /// Ask the system to fetch an item without reading it.
    ///
    /// - Parameters:
    ///     - url: The item to fetch.
    ///
    /// - Returns: `true` if the system accepted the request.
    ///
    public static func startDownloading(_ url: URL) -> Bool {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)

            return true
        } catch {
            return false
        }
    }

    ///
    /// Remove the local content of an item, leaving the placeholder behind.
    ///
    /// - Parameters:
    ///     - url: The item to evict.
    ///
    /// - Returns: `true` if the system accepted the request.
    ///
    public static func evict(_ url: URL) -> Bool {
        do {
            try FileManager.default.evictUbiquitousItem(at: url)

            return true
        } catch {
            return false
        }
    }
}
