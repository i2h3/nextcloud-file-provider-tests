// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// How real the item (or its parent) is to the File Provider framework.
///
/// This axis is deliberately *not* one boolean per question. "Was the item enumerated?" and "was it materialized?" are not independent — materialization implies enumeration — so the two questions are collapsed into this one ordered level instead of two flags which could contradict each other.
///
/// Ordered: each value implies everything before it is already true. ``materialized`` implies enumerated, which is why `(not enumerated, materialized)` is not representable here — it is an impossible state, not a matrix cell.
///
/// Deliberately *not* `Comparable`: ``dataless`` and ``evicted`` are equally realized but distinct, so any total order over these cases would be a lie. Use ``hasContent`` and ``isKnown`` instead.
///
/// Which levels are available to a cell depends on what the level describes rather than on the level itself: ``Constraints`` answers that separately for an item and for a container, and ``Realization`` is what records which of the two a given cell means.
///
public enum RealizationLevel: String, CaseIterable, Hashable, Sendable {
    ///
    /// Never enumerated — the framework has no item for it at all.
    ///
    /// Only reachable for the item under test, and only where the operation does not require it to exist already. No container this model can place is ever in this state: ``Location`` offers only the domain root and a directory directly beneath it, and the root is enumerated as soon as the domain mounts, which reveals that directory.
    ///
    case unknown

    ///
    /// A placeholder exists: metadata and version known, content not downloaded.
    ///
    /// The state every depth-one container is in at t=0, and the state a metadata-only operation is expected to leave untouched — a remote rename which quietly materializes a placeholder is the classic regression the ``Oracle/realizationState`` clause is there to catch.
    ///
    case dataless

    ///
    /// Content present on disk. For a directory this means *shallow*: the container itself is materialized, its children are not.
    ///
    case materialized

    ///
    /// Directories only: recursively materialized, children included. Reached child-by-child, because `requestDownloadForItem` materializes a directory one level down only.
    ///
    /// Emitted only where "recursively materialized" is genuinely a different state from ``materialized``, which is to say for a folder with children: an empty folder has none, and a bundle materializes as a unit.
    ///
    case materializedDeep

    ///
    /// Was materialized, content dropped to reclaim space, still known. Behaves like ``dataless`` for metadata operations but takes a different re-fetch path — historically a bug magnet.
    ///
    /// This case is also the precedent which settles how history enters this model at all. It *is* a two-operation prefix, materialize then evict, collapsed into a single precondition value, and it earns its place because the residue it leaves is a distinguishable state rather than a sequence the matrix would have to replay.
    ///
    /// It is offered for the item under test only. A container is excluded, because folder eviction aborts non-deterministically on a non-evictable child, and a precondition which cannot be established reliably is not one a cell may rest on.
    ///
    case evicted

    // MARK: - Reading

    ///
    /// Whether content is present on disk right now.
    ///
    /// Read wherever a cell needs bytes to exist before it can be judged: it decides whether a content update is legal at all outside ``Origin/remote``, and whether the generator attaches the ``Oracle/contentMatch`` clause.
    ///
    public var hasContent: Bool {
        switch self {
            case .materialized, .materializedDeep: true
            case .unknown, .dataless, .evicted: false
        }
    }

    ///
    /// Whether the framework knows about the item at all.
    ///
    /// The line an ``Operation`` with ``Operation/requiresExistingItem`` cannot be placed on the wrong side of.
    ///
    public var isKnown: Bool {
        self != .unknown
    }
}
