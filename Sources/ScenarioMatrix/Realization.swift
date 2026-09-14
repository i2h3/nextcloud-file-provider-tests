// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Which object the realization precondition describes.
///
/// **The realization axis does not always describe the item under test.** This is the subtlety most easily lost, and it is the whole reason this type exists instead of a bare ``RealizationLevel`` on ``Scenario``. For a ``Operation/create`` the item does not exist yet, so what matters is the *parent*; for a ``Operation/move`` there are *two* parents, whose states can differ. Only for ``Operation/metadataUpdate``, ``Operation/contentUpdate`` and ``Operation/delete`` does the level describe the item itself.
///
/// A reader who takes a level for the item's state regardless of the operation will establish the wrong precondition and then watch the cell pass for the wrong reason, which is indistinguishable from coverage. So the operation decides which case is emitted, and every consumer asks this type rather than the level.
///
/// The distinction also decides which levels are on offer in the first place: ``Constraints`` answers that separately for an item and for a container, since a container is a directory and a directory cannot be evicted as a reliable precondition.
///
public enum Realization: Hashable, Sendable {
    ///
    /// For ``Operation/metadataUpdate``, ``Operation/contentUpdate``, ``Operation/delete`` — the item itself.
    ///
    /// The only case whose level is checked against the ``Origin`` and the ``Operation``, because those rules — an operation which needs an existing item, a content update which needs bytes on disk — are statements about the item and about nothing else.
    ///
    case item(RealizationLevel)

    ///
    /// For ``Operation/create`` — the container the item is created into.
    ///
    /// Its level comes from the container lattice and is filtered by ``Location``: the domain root is always materialized once the domain mounts, so it is the only level a root container may carry.
    ///
    case parent(RealizationLevel)

    ///
    /// For ``Operation/move`` — the source and destination containers.
    ///
    /// The two are drawn independently, so a move can start in a materialized container and land in a dataless one. This is the pair which makes ``Site/transfer(from:to:)`` and this case travel together in a ``Scenario``.
    ///
    case parents(source: RealizationLevel, destination: RealizationLevel)

    // MARK: - Reading

    ///
    /// Every level mentioned, for invariant checks and reporting.
    ///
    /// It exists so that a rule which cares about realization but not about whose realization it is can be written once. ``Constraints`` uses it to refuse a pinned cell which is not materialized, and the generator uses it to decide whether a cell has content worth comparing.
    ///
    public var levels: [RealizationLevel] {
        switch self {
            case let .item(level), let .parent(level): [level]
            case let .parents(source, destination): [source, destination]
        }
    }
}

// MARK: - CustomStringConvertible

extension Realization: CustomStringConvertible {
    ///
    /// Implementation for `CustomStringConvertible` conformance to name the precondition in a form which can be read by a human.
    ///
    /// The prefix is the point: it says out loud whether the level belongs to the item or to a container, so a case name never invites the reader to assume the item. This string is embedded in ``Scenario``'s own description, which is used as the test-case name, so it must not change unless the row it describes changes.
    ///
    public var description: String {
        switch self {
            case let .item(level): "item:\(level.rawValue)"
            case let .parent(level): "parent:\(level.rawValue)"
            case let .parents(source, destination): "parents:\(source.rawValue)->\(destination.rawValue)"
        }
    }
}
