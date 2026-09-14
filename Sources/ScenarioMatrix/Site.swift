// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// One placement, or the pair a `move` spans.
///
/// Every operation but a move happens in one place, and a move happens in two which may differ in every respect — which is why the site axis of a ``Scenario`` is this enum rather than a single ``Placement``. Carrying the pair here rather than as two loose fields is what lets the constraints, the generator and the oracles ask their questions of "the site" without each of them branching on the operation first.
///
public enum Site: Hashable, Sendable, CustomStringConvertible {
    ///
    /// The item stays where it is: one placement, for every operation except a move.
    ///
    case single(Placement)

    ///
    /// A move, from a source placement to a destination one.
    ///
    /// The two always differ in at least one dimension, because a move whose source and destination are equal is a rename, which is ``Operation/metadataUpdate`` and belongs to another quadrant.
    ///
    case transfer(from: Placement, to: Placement)

    ///
    /// Every placement this site touches, in source-then-destination order for a transfer.
    ///
    /// Read wherever a rule must hold of both ends of a move: a write is refused if *either* container refuses it, and ``ContentPolicy/pinnedInherited`` needs *every* placement to sit at ``Location/subdirectory``.
    ///
    public var placements: [Placement] {
        switch self {
            case let .single(placement): [placement]
            case let .transfer(from, to): [from, to]
        }
    }

    ///
    /// The placement a write lands in — the destination for a move.
    ///
    /// This is the container whose ``RealizationLevel`` is the precondition of a ``Operation/create``, since the item itself does not exist yet and cannot have one.
    ///
    public var target: Placement {
        switch self {
            case let .single(placement): placement
            case let .transfer(_, to): to
        }
    }

    ///
    /// True when a move crosses container types, which Nextcloud implements as copy+delete and which therefore changes the file id rather than preserving it.
    ///
    /// The ``Oracle/moveIdentity`` clause asserts exactly that consequence: the item is absent at the source and present at the destination, and the file id changes if and only if this is true.
    ///
    public var crossesContainerType: Bool {
        switch self {
            case .single: false
            case let .transfer(from, to): from.container.type != to.container.type
        }
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the site in a form which can be read by a human.
    ///
    /// Each placement renders itself, so this adds only which end is which. It is a part of what ``Scenario`` renders as its own description, which is used as the name of the test case, so it must not change unless the site it describes changes.
    ///
    public var description: String {
        switch self {
            case let .single(placement): "at:\(placement)"
            case let .transfer(from, to): "from:\(from) to:\(to)"
        }
    }
}
