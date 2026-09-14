// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Legality rules for the matrix.
///
/// These live in one place on purpose. Encoding them as predicates means impossible combinations are never *emitted*, rather than being emitted and then skipped — a suite full of skips reads as coverage it does not have, and hides the difference between "cannot happen" and "not yet tested".
///
/// Every rule below states the mechanism it comes from, because the non-obvious ones are the whole reason the matrix is a fraction of the naive Cartesian product.
///
/// ``Generator`` is the only caller. It walks the axis values a ``Phase`` declares drivable and asks these predicates, one by one, whether a combination may become a ``Scenario``; a combination refused here leaves no trace anywhere downstream — no row, no skip, no name in a report. Nothing in this type knows how a precondition would be established, which is what keeps the model free of any dependency on the harness that establishes it.
///
public enum Constraints {
    // MARK: - Admissibility of history

    //
    // Every cell is ONE operation applied to a freshly established precondition. That is a real limitation and it invites a "sequence" axis, which is the classic combinatorial explosion: even two-operation prefixes multiply the matrix by the square of the operation count before any state axis is applied.
    //
    // The gate that settles it, and that this model already obeys:
    //
    //     History is admissible ONLY where it leaves residue that cannot be expressed as a precondition state.
    //
    // `RealizationLevel.evicted` is the precedent — it *is* a two-operation prefix (materialize → evict) collapsed into a single precondition value, because the residue it leaves is a distinguishable state. By the same gate, materialize→evict→materialize, rename→rename-back and create→rename→delete are already covered: each step begins from a state this lattice enumerates, provided the harness settles between steps, which it must do regardless.
    //
    // History therefore enters this model as a named state value, the way `evicted` did, or not at all. Two residues are known to survive the gate and are recorded as deferred candidates rather than built: version lineage (a locally-created item carries a different baseVersion into its next operation than an enumerated one) and identifier reuse after delete-then-recreate-same-name. Neither is built, because no cell in this model has yet been executed.
    //

    // MARK: - Quadrant legality

    ///
    /// Whether a quadrant of the suite spine can hold cases at all.
    ///
    /// A `concurrent` (conflict) origin needs an existing item to be changed from both sides at once, so it cannot apply to `create`. It is also only meaningful where the two sides can actually disagree: content, metadata, or existence.
    ///
    /// ``Quadrant/allCases`` filters every ``Origin`` × ``Operation`` pair through this, so a quadrant refused here is never offered to ``Generator/matrix(for:)`` and never names a group of tests.
    ///
    /// - Parameters:
    ///     - quadrant: The origin and operation pair to judge.
    ///
    /// - Returns: `true` when the pair describes a situation that can occur.
    ///
    public static func isLegal(_ quadrant: Quadrant) -> Bool {
        guard quadrant.origin == .concurrent else {
            return true
        }

        switch quadrant.operation {
            case .contentUpdate, .metadataUpdate, .delete: return true
            case .create, .move: return false
        }
    }

    // MARK: - Realization

    ///
    /// Which realization levels a given object may plausibly be in.
    ///
    /// `materializedDeep` only exists where "recursively materialized" differs from "materialized": an empty folder has no children, and a bundle materializes as a unit.
    ///
    /// This is the menu ``Generator`` draws from before it narrows the result with ``isLegal(itemRealization:origin:operation:kind:)`` or ``isLegal(containerRealization:location:)``, so a level missing from here is one no ``Scenario`` can carry under any origin, operation or location.
    ///
    /// - Parameters:
    ///     - kind: What sort of thing the item is, which decides via ``ItemKind/hasDistinctDeepMaterialization`` whether ``RealizationLevel/materializedDeep`` is a state of its own.
    ///     - subject: Whether the levels describe the item under test or a container holding it.
    ///
    /// - Returns: The levels worth enumerating, in the order the matrix presents them.
    ///
    public static func realizationLevels(for kind: ItemKind, subject: RealizationSubject) -> [RealizationLevel] {
        switch subject {
            case .item:
                var levels: [RealizationLevel] = [.unknown, .dataless, .materialized, .evicted]

                if kind.hasDistinctDeepMaterialization {
                    levels.insert(.materializedDeep, at: 3)
                }

                return levels

            case .container:
                // A container is a directory. `evicted` is excluded: folder eviction aborts non-deterministically on a non-evictable child, so it is not a state a test can establish as a reliable precondition.
                return [.unknown, .dataless, .materialized, .materializedDeep]
        }
    }

    ///
    /// Whether an item-level realization is legal for this origin/operation.
    ///
    /// Two mechanisms are encoded here, both of them about what the framework can be asked to do rather than about what is interesting to test. An operation on an existing item needs the framework to know the item at all, and bytes cannot be edited before they have been downloaded.
    ///
    /// Applied by ``Generator`` to every ``Realization/item(_:)`` precondition it forms, immediately after ``realizationLevels(for:subject:)`` has offered the level. The container counterpart is ``isLegal(containerRealization:location:)``.
    ///
    /// - Parameters:
    ///     - level: The state the item is in before the operation is performed.
    ///     - origin: Where the change comes from, which decides whether the local side has to hold the bytes.
    ///     - operation: What is done to the item.
    ///     - kind: What sort of thing the item is.
    ///
    /// - Returns: `true` when the precondition is one a test can establish and the operation can then exercise.
    ///
    public static func isLegal(itemRealization level: RealizationLevel, origin: Origin, operation: Operation, kind _: ItemKind) -> Bool {
        // An operation on an existing item needs the framework to know the item.
        if operation.requiresExistingItem, level == .unknown {
            return false
        }

        // You cannot edit bytes you have not downloaded. macOS materializes on open, so (local, contentUpdate, dataless) is not a distinct case — it degenerates into "materialize, then change".
        if operation == .contentUpdate, origin != .remote, !level.hasContent {
            return false
        }

        // A local change requires the item to be present locally in some form; that is already covered by the `unknown` rule above.
        return true
    }

    ///
    /// Whether a container-level realization is legal at this location.
    ///
    /// Two rules, and the second was found by measurement rather than by reasoning:
    ///
    /// 1. The domain root is always enumerated once the domain mounts, so an unknown or dataless root is degenerate. (Confirmed against a running harness: its clean-room build enumerates the root before any test body executes.)
    /// 2. **`unknown` is unreachable for any container this model can place.** `Location` offers only `root` and `subdirectory`, so every container sits *directly* under the always-enumerated root — and that enumeration reveals it. A depth-1 container is therefore `dataless` at t=0 and never `unknown`. Emitting those cells produced tests whose precondition could not be established, which pass for the wrong reason rather than failing.
    ///
    /// Reaching a genuinely `unknown` container needs a depth-2 `Location`, which is not obviously clean either: creating into `domain/a/b` performs a path lookup through `a`, which may itself enumerate. Deferred rather than assumed.
    ///
    /// This is what makes ``Realization/parent(_:)`` and ``Realization/parents(source:destination:)`` narrower than the menu ``realizationLevels(for:subject:)`` returns, and it is the reason ``Generator`` carries no live branch for a `create` into an unknown parent.
    ///
    /// - Parameters:
    ///     - level: The state the container is in before the operation is performed.
    ///     - location: How deep the container sits within the domain.
    ///
    /// - Returns: `true` when the precondition is one the harness can actually put the container into.
    ///
    public static func isLegal(containerRealization level: RealizationLevel, location: Location) -> Bool {
        if location == .root {
            return level == .materialized
        }

        return level != .unknown
    }

    // MARK: - Item shape

    ///
    /// Sizes worth testing for a kind and operation.
    ///
    /// Size only selects an upload path, so it matters where bytes are written and nowhere else.
    ///
    /// The result is an optional on purpose: ``ItemProfile/init(kind:size:)`` refuses a size on anything but a ``ItemKind/file``, so `nil` is the value that lets a directory through rather than the absence of an answer.
    ///
    /// - Parameters:
    ///     - kind: What sort of thing the item is; only a file has a size of its own.
    ///     - operation: What is done to the item, which decides whether bytes are written at all.
    ///     - available: The sizes the current ``Phase`` can drive.
    ///
    /// - Returns: One entry per cell the size axis should contribute, or `[nil]` where the axis does not apply.
    ///
    public static func sizes(for kind: ItemKind, operation: Operation, available: [FileSize]) -> [FileSize?] {
        guard kind == .file else {
            return [nil]
        }

        switch operation {
            case .create, .contentUpdate: return available.map(\.self)
            case .metadataUpdate, .delete, .move:
                // The bytes are not touched, so one representative size is enough; more would multiply the matrix without exercising a new path.
                return [.small]
        }
    }

    ///
    /// Whether an operation applies to this kind of item at all.
    ///
    /// The outermost filter of ``Generator/scenarios(for:phase:)``: a kind refused here contributes nothing to the quadrant, before any site, realization or policy is considered.
    ///
    /// - Parameters:
    ///     - operation: What is done to the item.
    ///     - kind: What sort of thing the item is.
    ///
    /// - Returns: `true` when the operation has something to act on.
    ///
    public static func isLegal(operation: Operation, kind: ItemKind) -> Bool {
        // A directory has no content of its own to replace. A bundle does, in the sense that editing inside it changes what the Finder presents as one item — a real and bug-prone path, so it stays in.
        if operation == .contentUpdate, !kind.hasOwnContent {
            return false
        }

        return true
    }

    // MARK: - Content policy

    ///
    /// Whether a content policy can coexist with a realization state.
    ///
    /// An effective-pinned item is, in steady state, materialized. Pinned-and-dataless is a *transient* state during the apply-pin → materialize transition, not a precondition a test can sit on, so it is not a matrix cell.
    ///
    /// Every level a ``Realization`` mentions is checked, which is what makes a `move` between two containers of differing state answer honestly: a pinned cell survives only if both ends hold content. ``RealizationLevel/unknown`` is permitted because pinning says nothing about a container the framework has not seen.
    ///
    /// - Parameters:
    ///     - policy: The pin state under test, effective-pinned or not per ``ContentPolicy/isEffectivelyPinned``.
    ///     - realization: The precondition whose levels must be compatible with that pin.
    ///
    /// - Returns: `true` when the pair is a steady state rather than a moment in a transition.
    ///
    public static func isLegal(contentPolicy policy: ContentPolicy, realization: Realization) -> Bool {
        guard policy.isEffectivelyPinned else {
            return true
        }

        return realization.levels.allSatisfy { $0.hasContent || $0 == .unknown }
    }

    ///
    /// Pin inheritance is only observable when there is an ancestor to inherit from.
    ///
    /// ``ContentPolicy/pinnedInherited`` exists to exercise the walk up the tree, and an item sitting in ``Location/root`` has nothing above it to walk to, so the cell would assert the resolution of a pin that was never placed. Both ends of a `move` are required to be below the root, since either placement would otherwise make the inheritance unobservable at that end.
    ///
    /// - Parameters:
    ///     - policy: The pin state under test.
    ///     - site: The placement, or the source and destination pair a `move` spans.
    ///
    /// - Returns: `true` when the pin can actually be inherited at every placement involved.
    ///
    public static func isLegal(contentPolicy policy: ContentPolicy, site: Site) -> Bool {
        guard policy == .pinnedInherited else {
            return true
        }

        return site.placements.allSatisfy { $0.location == .subdirectory }
    }

    // MARK: - Move

    ///
    /// Whether a pair of placements describes a move at all.
    ///
    /// A move must actually move something: source and destination differ in at least one dimension. A same-container, same-location "move" is a rename, which is `metadataUpdate`.
    ///
    /// Used by ``Generator`` when it forms the ``Site/transfer(from:to:)`` values of the move quadrants, so the degenerate pair never becomes a ``Scenario`` that duplicates the metadata-update coverage.
    ///
    /// - Parameters:
    ///     - source: Where the item starts.
    ///     - destination: Where the item ends up.
    ///
    /// - Returns: `true` when the two differ in depth, container type or permission.
    ///
    public static func isLegalMove(from source: Placement, to destination: Placement) -> Bool {
        source != destination
    }

    // MARK: - Filename encoding

    ///
    /// Encodings worth testing for an origin and operation.
    ///
    /// Gated tightly on purpose. Encoding only bites where a name is *introduced or changed by the server*: the client must then decide a normalisation form, and that decision is what can produce a duplicate. A locally-originated name never round-trips through that decision, and an operation that does not touch the name cannot exercise it at all.
    ///
    /// What survives this gate is narrowed once more downstream, where ``Generator`` collapses the remaining encoding cells to one representative per operation and kind.
    ///
    /// - Parameters:
    ///     - origin: Where the change comes from; only ``Origin/remote`` introduces a name the client must normalise.
    ///     - operation: What is done to the item, which decides whether a name is introduced or changed.
    ///     - available: The encodings the current ``Phase`` can drive.
    ///
    /// - Returns: The baseline `nil` alone where the axis does not apply, otherwise the baseline followed by the variants.
    ///
    public static func encodingValues(for origin: Origin, operation: Operation, available: [FilenameEncoding]) -> [FilenameEncoding?] {
        guard origin == .remote else {
            return [nil]
        }

        switch operation {
            case .create, .metadataUpdate, .move:
                // `nil` is the baseline: an ordinary name for which encoding is not a factor. It must be kept, because the encoding variants are collapsed to a handful of representatives and would otherwise *replace* the realization/site/size coverage of these quadrants rather than adding to it.
                return [nil] + available.map(\.self)
            case .contentUpdate, .delete: return [nil]
        }
    }

    // MARK: - Trash

    ///
    /// The trash axis only varies where something is deleted.
    ///
    /// Whether the server keeps deleted items is a property of the server profile a run deploys, so crossing it with anything but ``Operation/delete`` would deploy two servers to observe one behaviour. Where it does apply, the value chosen also decides the ``Contract`` the trash oracle is held to, because a server without a trash bin leaves the destination of a deleted item undetermined.
    ///
    /// - Parameters:
    ///     - operation: What is done to the item.
    ///     - available: The trash configurations the current ``Phase`` can drive.
    ///
    /// - Returns: One entry per cell the trash axis should contribute, or `[nil]` where the axis does not apply.
    ///
    public static func trashValues(for operation: Operation, available: [TrashSupport]) -> [TrashSupport?] {
        operation == .delete ? available.map(\.self) : [nil]
    }
}
