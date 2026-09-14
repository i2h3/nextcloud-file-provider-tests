// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Where the change came from.
///
/// This is one of the orthogonal axes of the File Provider test matrix, and together with ``Operation`` it forms the ``Quadrant`` which is the spine of the suite. The quadrant is what fixes the direction the oracles read in, local to server or server to local, and it is also how a failure is described in practice: "a remote move is broken", rather than the identity of a single cell.
///
/// Not every pairing of this axis with ``Operation`` can legally hold cases, which is why ``Quadrant`` filters itself through ``Constraints`` rather than taking the full product. The axis reaches beyond the quadrant as well: ``FilenameEncoding`` is gated on ``remote``, because a normalisation decision is only made where a name arrives from the server.
///
public enum Origin: String, CaseIterable, Hashable, Sendable {
    ///
    /// Change made on this Mac, expected to propagate to the server.
    ///
    /// The item is already present locally in some form, so the item-level ``RealizationLevel`` of such a cell is never ``RealizationLevel/unknown``.
    ///
    case local

    ///
    /// Change made on the server, expected to propagate to this Mac.
    ///
    /// The only origin under which a name is introduced or changed by the server, which is why it is the only one that carries a ``FilenameEncoding``.
    ///
    case remote

    ///
    /// Simultaneous local *and* remote change to the same item — the conflict case.
    ///
    /// It needs an existing item to be changed from both sides at once, so it cannot apply to ``Operation/create``, and it is only meaningful where the two sides can actually disagree: content, metadata, or existence. ``Constraints`` refuses the remaining quadrants outright, and a cell with this origin is the one that carries the ``Oracle/conflictResolution`` clause.
    ///
    case concurrent
}
