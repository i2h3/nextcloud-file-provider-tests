// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// "Keep Always Downloaded" and its inheritance.
///
/// Maps onto `NSFileProviderContentPolicy`. An item is *effective-pinned* when it, or any ancestor, is pinned — resolution walks up the tree, which is exactly what ``pinnedInherited`` exercises.
///
/// Note this axis is **observed, not driven**: `contentPolicy` is read-only on `NSFileProviderItem` with no fields bit and no URL resource key, so a test cannot set it. Phase A therefore only asserts that the *default* resolution is correct.
///
/// One axis of a ``Scenario``, carried as ``Scenario/contentPolicy``, and which of its values a run may use comes from ``Phase/contentPolicies``. Two constraints prune it against the other axes: a pin cannot be paired with a ``RealizationLevel`` that has no content, because pinned-and-dataless is a transient of the apply-pin transition rather than a precondition a test can sit on, and ``pinnedInherited`` cannot be paired with a ``Site`` that touches ``Location/root``, where there is no ancestor to inherit from.
///
public enum ContentPolicy: String, CaseIterable, Hashable, Sendable {
    ///
    /// No pin anywhere up the chain — lazily downloaded and evictable.
    ///
    /// The baseline, and the only value a run offers before ``Phase/c``, since a pin cannot be established from a test process.
    ///
    case `default`

    ///
    /// The item itself is pinned.
    ///
    /// Kept distinct from ``pinnedInherited`` because resolving a pin set on the item is the trivial half of the walk up the tree, and only the other half can be wrong quietly.
    ///
    case pinnedDirect

    ///
    /// An ancestor is pinned; the item inherits it. The inheritance resolution is the point.
    ///
    /// Only observable where an ancestor exists, which is why this value is kept to sites whose placements all sit at ``Location/subdirectory``.
    ///
    case pinnedInherited

    ///
    /// Whether the item ends up effective-pinned, and so must be materialized and resist eviction.
    ///
    /// This is what ``Constraints`` reads to reject a pin over a realization state with no content, and what the ``Oracle/contentPolicyInheritance`` clause asserts the consequences of. That clause runs on every generated cell, including the ones where this is `false`: assuming the default resolution is correct is how inheritance bugs survive.
    ///
    public var isEffectivelyPinned: Bool {
        self != .default
    }
}
