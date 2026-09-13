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
    /// The identity the server gives the item, which survives a rename and a move within one storage.
    ///
    /// This is the field that makes an entire class of defect visible, and without it that class is invisible by construction. A save performed the way applications perform one — write a temporary file, then replace the original with it — is not a modification of the existing item. It is a creation followed by a rename over the top, and the File Provider contract is explicit that reusing an identifier removes the item which held it. On a Nextcloud server the identity is not a bookkeeping detail: shares, favourites, comments and the version history all hang off it, so an item which comes back with a new identity has silently lost all of them.
    ///
    /// A test which compares content passes anyway. It is exactly the right content, under a name which is exactly right, in an item which is no longer the same item. Asserting this across a rename or a save is the only way that failure is ever seen.
    ///
    /// Read from `oc:fileid`. Worth stating because the names invite the opposite: Rainmaker's `Item.instanceId` is `oc:fileid` and its `Item.id` is `oc:id`, which is inverted from what either name suggests. Asserting identity on the wrong one of those produces a test which passes for the wrong reason — the failure mode hardest to notice, because nothing is red.
    ///
    public let fileIdentifier: String?

    ///
    /// The entity tag, which changes when the content changes and not when the name does.
    ///
    /// The counterpart to ``fileIdentifier``: together they say whether an operation was the metadata change it claimed to be, or a content change wearing its clothes.
    ///
    public let entityTag: String?

    ///
    /// When the server believes the item was last modified.
    ///
    /// Kept because an upload is supposed to preserve it, and nothing in this suite has ever checked.
    ///
    public let modifiedAt: Date?

    ///
    /// Create an entry of a server-side listing.
    ///
    /// The identity fields carry defaults so that a comparison which does not care about identity — and most do not — reads as it always did.
    ///
    /// - Parameters:
    ///     - name: The name of the entry as the server spells it.
    ///     - isDirectory: Whether the entry is a directory.
    ///     - size: The size in bytes, or `nil` for a directory.
    ///     - fileIdentifier: The server's identity for the item, from `oc:fileid`.
    ///     - entityTag: The entity tag.
    ///     - modifiedAt: When the server believes it was last modified.
    ///
    public init(name: String, isDirectory: Bool, size: Int64?, fileIdentifier: String? = nil, entityTag: String? = nil, modifiedAt: Date? = nil) {
        self.entityTag = entityTag
        self.fileIdentifier = fileIdentifier
        self.isDirectory = isDirectory
        self.modifiedAt = modifiedAt
        self.name = name
        self.size = size
    }
}
