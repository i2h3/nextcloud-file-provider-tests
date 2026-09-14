// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// What sort of thing the item is.
///
/// One of the axes a ``Scenario`` is built from, and the one the other item-shaped decisions hang off: ``Constraints/isLegal(operation:kind:)`` rules an ``Operation`` out for a kind which cannot carry it, ``Constraints/sizes(for:operation:available:)`` offers a ``FileSize`` only where there are bytes of the item's own, and ``Constraints/realizationLevels(for:subject:)`` offers ``RealizationLevel/materializedDeep`` only for the single kind where that state differs from plain materialization.
///
/// Which kinds are in scope for a run is a decision of the ``Phase``, through ``Phase/itemKinds``.
///
public enum ItemKind: String, CaseIterable, Hashable, Sendable {
    ///
    /// A regular file, which has bytes of its own.
    ///
    /// The only kind which carries a ``FileSize``, which is exactly the rule ``ItemProfile/init(kind:size:)`` enforces.
    ///
    case file

    ///
    /// A directory with no children.
    ///
    /// The baseline directory case: it exercises the container paths without dragging recursion into them, and "recursively materialized" says nothing about it, which is why ``hasDistinctDeepMaterialization`` is `false` here.
    ///
    case folderEmpty

    ///
    /// A directory with children.
    ///
    /// Delete and move recurse over children whose own realization states vary — a distinct and bug-prone path.
    ///
    /// It is the only kind for which ``RealizationLevel/materializedDeep`` is a state of its own, and the one the ``Generator`` names explicitly when it writes the rationale for a delete: the children must go with the parent and leave no orphaned placeholders behind, which is what ``Oracle/noDuplicatesOrOrphans`` checks.
    ///
    case folderWithChildren

    ///
    /// A directory the Finder presents as a single item (`.app`, `.key`). Materializes as a unit.
    ///
    /// Because the system treats it as one item, it counts as having content of its own — see ``hasOwnContent`` — so ``Operation/contentUpdate`` stays legal for it even though it is a directory.
    ///
    case bundle

    ///
    /// Whether the item is a directory rather than a regular file.
    ///
    /// Every kind but ``file`` is one, a ``bundle`` included: the Finder presents a bundle as a single item, but the framework and the server both see a tree. A directory has no size of its own, which is the other half of the rule ``ItemProfile`` enforces.
    ///
    public var isDirectory: Bool {
        self != .file
    }

    ///
    /// Whether "recursively materialized" is a meaningful distinct state.
    ///
    /// An empty folder has no children, and a bundle materializes atomically.
    ///
    /// This is what ``Constraints/realizationLevels(for:subject:)`` consults before it adds ``RealizationLevel/materializedDeep`` to the levels an item may be in, so a `false` here removes a whole column of cells rather than producing cells which are skipped.
    ///
    public var hasDistinctDeepMaterialization: Bool {
        self == .folderWithChildren
    }

    ///
    /// Whether the item has bytes of its own that can be replaced.
    ///
    /// Read by ``Constraints/isLegal(operation:kind:)`` to rule ``Operation/contentUpdate`` out for a directory, which has no content to replace. A ``bundle`` answers `true` because editing inside it changes what the Finder presents as one item, which is a real and bug-prone path.
    ///
    public var hasOwnContent: Bool {
        self == .file || self == .bundle
    }
}
