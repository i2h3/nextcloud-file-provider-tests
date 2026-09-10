// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One entry of a server-side directory listing, reduced to what a comparison needs.
///
/// The server is reached through Rainmaker, which lives in ``ServerHarness``. This harness stays free of that dependency so that its unit tests need no server at all, so the listing is handed in as values of this type instead of as Rainmaker's own model.
///
public struct RemoteEntry: Hashable, Sendable {
    ///
    /// Whether the entry is a directory.
    ///
    public let isDirectory: Bool

    ///
    /// The name of the entry, exactly as the server spells it.
    ///
    /// The spelling is kept byte for byte because macOS hands out decomposed names while the server stores whatever was uploaded, and whether those two agree is itself under test.
    ///
    public let name: String

    ///
    /// The size in bytes, or `nil` for a directory.
    ///
    public let size: Int64?

    ///
    /// Create an entry of a server-side listing.
    ///
    /// - Parameters:
    ///     - name: The name of the entry as the server spells it.
    ///     - isDirectory: Whether the entry is a directory.
    ///     - size: The size in bytes, or `nil` for a directory.
    ///
    public init(name: String, isDirectory: Bool, size: Int64?) {
        self.isDirectory = isDirectory
        self.name = name
        self.size = size
    }
}
