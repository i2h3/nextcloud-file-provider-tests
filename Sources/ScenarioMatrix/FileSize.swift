// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// File size class, which selects the upload path.
///
/// A sub-axis of ``ItemKind`` rather than a top-level one: a size is only carried where there is something to size, which ``ItemProfile/init(kind:size:)`` enforces by refusing any other pairing.
///
/// Because size selects a path and nothing else, it is varied only where bytes are actually written. ``Constraints/sizes(for:operation:available:)`` returns the full set for ``Operation/create`` and ``Operation/contentUpdate``, and one representative size for the operations which leave the bytes alone — more would multiply the matrix without exercising a new path. The set available to a run comes from ``Phase/fileSizes``.
///
public enum FileSize: String, CaseIterable, Hashable, Sendable {
    ///
    /// No bytes at all.
    ///
    /// Still a file, so it still carries a size in an ``ItemProfile``, and worth its own cell because "nothing to upload" is a case a client can quietly skip rather than perform.
    ///
    case empty

    ///
    /// Below the chunking threshold, so it goes up in a single request.
    ///
    /// The representative size for every operation which does not touch the content, which is why it is the one ``Constraints/sizes(for:operation:available:)`` hands back for a rename, a delete or a move.
    ///
    case small

    ///
    /// Above the chunking threshold, so it exercises Nextcloud's chunked-upload protocol.
    ///
    /// A different upload path, with its own assembly step on the server, and therefore its own way of ending up with content which does not match — which is what ``Oracle/contentMatch`` is there to catch.
    ///
    case large
}
