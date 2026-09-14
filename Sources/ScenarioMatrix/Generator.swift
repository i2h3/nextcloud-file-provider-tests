// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// Builds the matrix.
///
/// The matrix is *generated*, never hand-maintained. A hand-written grid rots: it silently keeps impossible rows, drifts from the constraints, and makes adding an axis a rewrite. Here the axes and the rules are the source of truth, and the row list is a derived artifact.
///
/// This is the only type of the model which composes the others. It walks the axis values a ``Phase`` declares drivable, asks ``Constraints`` whether a combination may exist at all, attaches the ``Expectation`` which says what the combination must do and why it is worth running, and emits one ``Scenario`` per surviving cell, grouped by the ``Quadrant`` the suite is organised along. Nothing here knows how a precondition is established or how an oracle is evaluated, which is what keeps the model free of any dependency on the harness that does both.
///
/// Two narrowings happen after the constraints have spoken, and they are the difference between coverage and cell count: expected rejections collapse to one representative per origin, operation, kind and site, and encoding variants to one per operation and kind. See `collapseRejections(in:)` and `collapseEncodings(in:)` for what is kept distinct and why.
///
public enum Generator {
    ///
    /// Every legal cell for a phase, grouped by quadrant, in deterministic order.
    ///
    /// A quadrant is only visited when the phase declares both its ``Origin`` and its ``Operation`` drivable, and it only reaches the result when it turned out to hold cells at all. So the returned dictionary carries no empty groups, and a missing key is the honest statement that this phase can build nothing there — never that the quadrant is uninteresting.
    ///
    /// - Parameters:
    ///     - phase: Which axis values the harness can currently establish.
    ///
    /// - Returns: The scenarios of every quadrant which holds any, keyed by that quadrant.
    ///
    public static func matrix(for phase: Phase) -> [Quadrant: [Scenario]] {
        var result: [Quadrant: [Scenario]] = [:]

        for quadrant in Quadrant.allCases where phase.origins.contains(quadrant.origin) && phase.operations.contains(quadrant.operation) {
            let scenarios = self.scenarios(for: quadrant, phase: phase)

            if !scenarios.isEmpty {
                result[quadrant] = scenarios
            }
        }

        return result
    }

    ///
    /// Every legal cell for one quadrant, in deterministic order.
    ///
    /// Order is stable so the snapshot is reviewable in diffs: a new row shows up as an insertion, not as a reshuffle.
    ///
    /// The nesting of the loops is the shape of the matrix itself — kind, then size, then site, then realization, then content policy, then trash and encoding — and every level asks ``Constraints`` whether to go on, so an impossible combination is abandoned as early as the mechanism which rules it out allows and never becomes a row that is emitted and then skipped. What survives is handed the ``Expectation`` of its cell and then passed through the two equivalence collapses.
    ///
    /// - Parameters:
    ///     - quadrant: The origin and operation pair whose cells are wanted.
    ///     - phase: Which axis values the harness can currently establish.
    ///
    /// - Returns: The scenarios of this quadrant, empty where the quadrant is illegal or where the phase can build none of its cells.
    ///
    public static func scenarios(for quadrant: Quadrant, phase: Phase) -> [Scenario] {
        guard Constraints.isLegal(quadrant) else {
            return []
        }

        let operation = quadrant.operation
        let origin = quadrant.origin
        var scenarios: [Scenario] = []

        for kind in phase.itemKinds {
            guard Constraints.isLegal(operation: operation, kind: kind) else {
                continue
            }

            for size in Constraints.sizes(for: kind, operation: operation, available: phase.fileSizes) {
                guard let item = ItemProfile(kind: kind, size: size) else {
                    continue
                }

                for site in sites(for: operation, phase: phase) {
                    for realization in realizations(for: operation, kind: kind, site: site) {
                        guard isLegal(realization, origin: origin, operation: operation, kind: kind) else {
                            continue
                        }

                        for policy in phase.contentPolicies {
                            guard Constraints.isLegal(contentPolicy: policy, realization: realization) else {
                                continue
                            }

                            guard Constraints.isLegal(contentPolicy: policy, site: site) else {
                                continue
                            }

                            for trash in Constraints.trashValues(for: operation, available: phase.trashSupport) {
                                for encoding in Constraints.encodingValues(for: origin, operation: operation, available: phase.filenameEncodings) {
                                    scenarios.append(Scenario(origin: origin, operation: operation, realization: realization, contentPolicy: policy, site: site, item: item, trash: trash, encoding: encoding, expected: expectation(origin: origin, operation: operation, realization: realization, contentPolicy: policy, site: site, item: item, trash: trash)))
                                }
                            }
                        }
                    }
                }
            }
        }

        return collapseEncodings(in: collapseRejections(in: scenarios))
    }

    // MARK: - Equivalence collapsing

    ///
    /// Collapses expected-rejection cells to one representative per equivalence class.
    ///
    /// This is the difference between full coverage and a padded cell count. When a container refuses a write, the refusal is decided by permission *before* the bytes, the realization state, the pin, or the trash configuration can matter. Enumerating "write into a read-only share" once per file size × realization × policy therefore adds thousands of cells that all exercise the same single code path.
    ///
    /// What is kept distinct is what can genuinely change a refusal: who refused (which end of a move, which container type and permission), what kind of item it was, and which operation from which origin. Everything else collapses to a representative.
    ///
    /// A cell whose ``Expectation/outcome`` is ``Outcome/success`` is never a member of a class and always survives, so this only ever thins the refusals of a quadrant.
    ///
    /// - Parameters:
    ///     - scenarios: The cells of one quadrant, before collapsing.
    ///
    /// - Returns: The same cells in the same order, with every rejection beyond the first of its class removed.
    ///
    private static func collapseRejections(in scenarios: [Scenario]) -> [Scenario] {
        var seen: Set<RejectionClass> = []

        return scenarios.filter { scenario in
            guard scenario.expected.outcome == .rejection else {
                return true
            }

            return seen.insert(RejectionClass(scenario)).inserted
        }
    }

    ///
    /// Collapses encoding cells to one representative per equivalence class.
    ///
    /// Normalisation is decided by the client's name-handling code, which does not consult the file's size, its realization state, its pin, or which container it sits in. Crossing the encoding values with all of those would multiply the matrix while re-running one code path, so only what can plausibly change the normalisation decision is kept distinct: the operation that introduces the name, and the kind of item being named.
    ///
    /// The baseline cells, the ones ``Constraints/encodingValues(for:operation:available:)`` emits as `nil`, are never members of a class and always survive. That is deliberate: they are what carries the realization, site and size coverage of the affected quadrants, which the collapsed encoding variants would otherwise replace rather than extend.
    ///
    /// - Parameters:
    ///     - scenarios: The cells of one quadrant, already thinned of redundant rejections.
    ///
    /// - Returns: The same cells in the same order, with every encoding variant beyond the first of its class removed.
    ///
    private static func collapseEncodings(in scenarios: [Scenario]) -> [Scenario] {
        var seen: Set<EncodingClass> = []

        return scenarios.filter { scenario in
            guard scenario.encoding != nil else {
                return true
            }

            return seen.insert(EncodingClass(scenario)).inserted
        }
    }

    ///
    /// The axes that can actually affect which normalisation form a name ends up in.
    ///
    /// The equivalence class of `collapseEncodings(in:)`: two cells agreeing on all three fields exercise the same name-handling decision of the client, so only the first of them is kept.
    ///
    private struct EncodingClass: Hashable {
        ///
        /// The operation which introduces or changes the name, from ``Scenario/operation``.
        ///
        let operation: Operation

        ///
        /// What sort of thing is being named, from the ``ItemProfile`` of the cell — a file and a directory need not travel the same naming path.
        ///
        let kind: ItemKind

        ///
        /// Which ``FilenameEncoding`` the name arrives in, carried so that the variants of one operation and kind do not collapse into each other.
        ///
        let encoding: FilenameEncoding?

        ///
        /// Derives the class one cell belongs to.
        ///
        /// - Parameters:
        ///     - scenario: The cell whose encoding equivalence class is wanted.
        ///
        init(_ scenario: Scenario) {
            operation = scenario.operation
            kind = scenario.item.kind
            encoding = scenario.encoding
        }
    }

    ///
    /// The axes that can actually affect whether — and by whom — a write is refused.
    ///
    /// The equivalence class of `collapseRejections(in:)`. Note what is absent: the file size, the realization state, the pin and the trash configuration, none of which the permission check consults before refusing.
    ///
    private struct RejectionClass: Hashable {
        ///
        /// Where the refused change came from, from ``Scenario/origin``.
        ///
        let origin: Origin

        ///
        /// What was attempted, from ``Scenario/operation``.
        ///
        let operation: Operation

        ///
        /// What sort of thing was written, from the ``ItemProfile`` of the cell.
        ///
        let kind: ItemKind

        ///
        /// Which container refused, and for a `move` which end of it — the ``Site`` carries both the type and the ``Permission`` the refusal is decided by.
        ///
        let site: Site

        ///
        /// Derives the class one cell belongs to.
        ///
        /// - Parameters:
        ///     - scenario: The cell whose rejection equivalence class is wanted.
        ///
        init(_ scenario: Scenario) {
            origin = scenario.origin
            operation = scenario.operation
            kind = scenario.item.kind
            site = scenario.site
        }
    }

    // MARK: - Sites

    ///
    /// Every place a phase can put an item, as the cross product of the locations and the containers it declares drivable.
    ///
    /// The raw material of `sites(for:phase:)` and nothing more: a ``Placement`` is never judged on its own, because legality at this level is a property of the ``Site`` formed from one or two of them.
    ///
    /// - Parameters:
    ///     - phase: Which axis values the harness can currently establish.
    ///
    /// - Returns: One placement per location and container pair, in the order the axes declare them.
    ///
    private static func placements(for phase: Phase) -> [Placement] {
        phase.locations.flatMap { location in
            phase.containers.map { Placement(location: location, container: $0) }
        }
    }

    ///
    /// The sites one operation can be performed at.
    ///
    /// Every operation but `move` happens at a single placement. A `move` spans two, so the placements are paired in both directions and the degenerate pairs are dropped by ``Constraints/isLegalMove(from:to:)`` — a move from a placement to itself is a rename, which this model covers as ``Operation/metadataUpdate``.
    ///
    /// - Parameters:
    ///     - operation: What is done to the item, which decides whether one placement is enough.
    ///     - phase: Which axis values the harness can currently establish.
    ///
    /// - Returns: One ``Site/single(_:)`` per placement, or one ``Site/transfer(from:to:)`` per legal ordered pair of them.
    ///
    private static func sites(for operation: Operation, phase: Phase) -> [Site] {
        let all = placements(for: phase)

        guard operation == .move else {
            return all.map { Site.single($0) }
        }

        return all.flatMap { source in
            all.compactMap { destination in
                guard Constraints.isLegalMove(from: source, to: destination) else {
                    return nil
                }

                return Site.transfer(from: source, to: destination)
            }
        }
    }

    // MARK: - Realizations

    ///
    /// The realization preconditions worth establishing for one operation at one site.
    ///
    /// This is where ``Realization`` stops being an axis about "the item" and becomes an axis about whichever object the operation actually depends on: the parent for a `create`, both parents for a `move`, the item itself for everything else. The container levels are filtered as they are formed, by ``Constraints/isLegal(containerRealization:location:)``; the item levels are not, because their legality also depends on the origin and is settled afterwards by `isLegal(_:origin:operation:kind:)`.
    ///
    /// - Parameters:
    ///     - operation: What is done to the item, which decides whose state the precondition describes.
    ///     - kind: What sort of thing the item is, which decides whether ``RealizationLevel/materializedDeep`` is a state of its own.
    ///     - site: Where the operation happens, whose ``Location`` decides which container states are establishable.
    ///
    /// - Returns: One precondition per state the cell should be run in, empty for a `move` whose site is not a transfer.
    ///
    private static func realizations(for operation: Operation, kind: ItemKind, site: Site) -> [Realization] {
        switch operation {
            case .create:
                // The item does not exist yet, so the precondition is the parent container's state.
                let placement = site.target

                return Constraints.realizationLevels(for: kind, subject: .container)
                    .filter { Constraints.isLegal(containerRealization: $0, location: placement.location) }
                    .map { Realization.parent($0) }

            case .move:
                // Two containers, whose states can differ independently.
                guard case let .transfer(from, to) = site else {
                    return []
                }

                let sources = Constraints.realizationLevels(for: kind, subject: .container)
                    .filter { Constraints.isLegal(containerRealization: $0, location: from.location) }
                let destinations = Constraints.realizationLevels(for: kind, subject: .container)
                    .filter { Constraints.isLegal(containerRealization: $0, location: to.location) }

                return sources.flatMap { source in
                    destinations.map { Realization.parents(source: source, destination: $0) }
                }

            case .metadataUpdate, .contentUpdate, .delete:
                return Constraints.realizationLevels(for: kind, subject: .item)
                    .map { Realization.item($0) }
        }
    }

    ///
    /// Whether a precondition which describes the item itself may be used for this cell.
    ///
    /// Only ``Realization/item(_:)`` is asked, because the container cases were already filtered against their ``Location`` when `realizations(for:kind:site:)` formed them, and the container rule has no further say once the level is legal there.
    ///
    /// - Parameters:
    ///     - realization: The precondition to judge.
    ///     - origin: Where the change comes from, which decides whether the local side must already hold the bytes.
    ///     - operation: What is done to the item.
    ///     - kind: What sort of thing the item is.
    ///
    /// - Returns: `true` when the precondition is one a test can establish and the operation can then exercise.
    ///
    private static func isLegal(_ realization: Realization, origin: Origin, operation: Operation, kind: ItemKind) -> Bool {
        switch realization {
            case let .item(level):
                Constraints.isLegal(itemRealization: level, origin: origin, operation: operation, kind: kind)
            case .parent, .parents:
                true
        }
    }

    // MARK: - Expectations

    ///
    /// What one cell must do, and which invariants prove it did.
    ///
    /// The outcome is decided first, because a refused write changes which oracles are meaningful: there is nothing to compare bytes against and no identity to preserve, while the permission which produced the refusal becomes the thing worth asserting. Every other clause is attached because the cell can actually exercise the invariant, never as a precaution — an oracle nobody can evaluate is a skip wearing the costume of coverage.
    ///
    /// Two of the clauses are held to an ``Contract/underdetermined(permitting:because:)`` contract rather than a determined one, both because the specification declines to pin the result down. See `trashContract(_:)` and `unpausedConflictContract`.
    ///
    /// - Parameters:
    ///     - origin: Where the change comes from.
    ///     - operation: What is done to the item.
    ///     - realization: The precondition the cell is established in.
    ///     - contentPolicy: The pin state under test.
    ///     - site: Where the operation happens, or the pair a `move` spans.
    ///     - item: What sort of thing is operated on, and how large it is.
    ///     - trash: Whether the server keeps deleted items, present only for a `delete`.
    ///
    /// - Returns: The outcome, the ordered oracle clauses and the rationale of this cell.
    ///
    private static func expectation(origin: Origin, operation: Operation, realization: Realization, contentPolicy: ContentPolicy, site: Site, item: ItemProfile, trash: TrashSupport?) -> Expectation {
        let refused = isRefused(operation: operation, site: site)
        var oracles: [OracleClause] = [
            OracleClause(.consistency, .determined),
            OracleClause(.noDuplicatesOrOrphans, .determined),
            OracleClause(.realizationState, .determined),
        ]

        // The pin oracle runs on every cell, including Phase A, where it asserts that the *default*
        // resolution up the ancestor chain is correct. Assuming it is correct is how inheritance
        // bugs survive.
        oracles.append(OracleClause(.contentPolicyInheritance, .determined))

        if !refused, item.kind.hasOwnContent, operation == .create || operation == .contentUpdate || realization.levels.contains(where: \.hasContent) {
            oracles.append(OracleClause(.contentMatch, .determined))
        }

        if site.placements.contains(where: { $0.container.type != .standard }) || refused {
            oracles.append(OracleClause(.sharePermission, .determined))
        }

        if operation == .delete {
            oracles.append(OracleClause(.trashPlacement, trashContract(trash)))
        }

        if operation == .move {
            oracles.append(OracleClause(.moveIdentity, .determined))
        }

        if !refused, operation == .metadataUpdate || operation == .contentUpdate {
            oracles.append(OracleClause(.identityStability, .determined))
        }

        if origin == .concurrent {
            oracles.append(OracleClause(.conflictResolution, unpausedConflictContract))
        }

        return Expectation(outcome: refused ? .rejection : .success, oracles: oracles, rationale: rationale(origin: origin, operation: operation, realization: realization, contentPolicy: contentPolicy, site: site, item: item, trash: trash, refused: refused))
    }

    ///
    /// Where a deleted item goes.
    ///
    /// With trash enabled this is pinned down. With trash disabled it is NOT: the API explicitly declines to say where the item ends up, so asserting a destination would be testing an implementation detail the specification leaves open. Only "it left the domain" is common to every permitted result.
    ///
    /// - Parameters:
    ///     - trash: Whether the server under test keeps deleted items.
    ///
    /// - Returns: ``Contract/determined`` wherever the destination is stated, otherwise the permitted set together with the citation which earns it.
    ///
    private static func trashContract(_ trash: TrashSupport?) -> Contract {
        guard trash == .without else {
            return .determined
        }

        return .underdetermined(
            permitting: ["removedPermanently", "providerDefinedDestination"],
            because: """
            NSFileProviderDomain.h:248 — with trash syncing unsupported the system decides how \
            to handle the trashing operation, and the destination is explicitly "not guaranteed \
            by API contract". The common invariant is that the item is gone from the domain and \
            the FPCK sweep is clean.
            """
        )
    }

    ///
    /// How a conflict on an *unpaused* item resolves.
    ///
    /// This is the case that is easy to get wrong: with no pause, none of the `NSFileManagerResumeSyncBehavior` policies apply — there is no ambient default, since the behaviour is a required parameter of `resumeSyncForUbiquitousItem`. The provider chooses, and every choice below is permitted. Asserting any single one of them is a test bug, and scoring one of them as data loss is how a correct client gets reported as defective.
    ///
    /// Carried by every cell of an ``Origin/concurrent`` quadrant, which is the only origin where both sides can change the same item at once.
    ///
    private static var unpausedConflictContract: Contract {
        .underdetermined(
            permitting: ["conflictCopy", "serverWon", "localWon"],
            because: """
            NSFileProviderReplicatedExtension.h:645 — for an unpaused item the provider resolves \
            via baseVersion and may legitimately pick a winner. Cf. NSFileManager.h:364-369, \
            where even the paused default (preserveLocalChanges) permits the server to "create a \
            conflict copy, or automatically pick the winner". The common invariant is that no \
            branch's bytes are lost without a recoverable copy.
            """
        )
    }

    ///
    /// A write is refused when it needs a permission the container does not grant. A move needs to remove from the source *and* create in the destination, so either end can refuse it.
    ///
    /// This is the whole of what decides between ``Outcome/rejection`` and ``Outcome/success``, and a refusal is a correct result rather than a failure — which is why the cells it produces are collapsed to representatives rather than enumerated in full.
    ///
    /// The operation is taken for the sake of the call site and is not consulted: the permission of the containers involved settles the question on its own, whatever is being attempted.
    ///
    /// - Parameters:
    ///     - operation: What is done to the item, which the refusal does not depend on.
    ///     - site: Where it is done, whose placements carry the ``Permission`` of their containers.
    ///
    /// - Returns: `true` when any container involved rejects writes.
    ///
    private static func isRefused(operation _: Operation, site: Site) -> Bool {
        site.placements.contains { $0.container.rejectsWrites }
    }

    ///
    /// Why this cell exists, in one sentence, carried into the snapshot as ``Expectation/rationale``.
    ///
    /// The branches are ordered by how much they say. A refusal is named first because it explains every cell it applies to; then come the combinations which encode a specific known-tricky behaviour; and only a cell nothing specific has been written about falls through to `unauthoredRationale(origin:operation:)`, which says so rather than pretending otherwise.
    ///
    /// - Parameters:
    ///     - origin: Where the change comes from.
    ///     - operation: What is done to the item.
    ///     - realization: The precondition the cell is established in.
    ///     - contentPolicy: The pin state under test.
    ///     - site: Where the operation happens, or the pair a `move` spans.
    ///     - item: What sort of thing is operated on, and how large it is.
    ///     - trash: Whether the server keeps deleted items, present only for a `delete`.
    ///     - refused: Whether the write is expected to be denied, as decided by `isRefused(operation:site:)`.
    ///
    /// - Returns: The sentence which describes what this cell pins down.
    ///
    private static func rationale(origin: Origin, operation: Operation, realization: Realization, contentPolicy: ContentPolicy, site: Site, item: ItemProfile, trash: TrashSupport?, refused: Bool) -> String {
        if refused {
            return "A \(operation.rawValue) into a read-only container must be refused: the local change is reverted and the server is left unchanged."
        }

        // The cells worth naming explicitly are the ones that encode a specific known-tricky
        // behaviour rather than a happy path.
        if origin == .remote, operation == .contentUpdate, case let .item(level) = realization {
            switch level {
                case .dataless:
                    return "A remote content change to a dataless placeholder must update metadata and version only — it must NOT materialize the item."
                case .evicted:
                    return "A remote content change to an evicted item must take the re-fetch path and end with content matching the server."
                case .materialized, .materializedDeep:
                    return "A remote content change to a materialized item must reconcile the downloaded bytes with the new server version."
                case .unknown:
                    break
            }
        }

        if origin == .concurrent {
            return "Both sides changed the same item: the conflict must be resolved with no data lost from either side."
        }

        if operation == .delete, item.kind == .folderWithChildren {
            return "Deleting a folder must remove its children recursively and leave no orphaned placeholders behind."
        }

        if operation == .delete, let trash {
            return trash == .with
                ? "A deleted item must be gone from the domain and present in the server trash bin."
                : "With trash disabled the item must be gone from the domain; the API gives no contract for where it goes, so nothing more is asserted."
        }

        if operation == .move, site.crossesContainerType {
            return "A move across container types is copy+delete on the server, so the file id changes; the item must be absent at the source and present at the destination."
        }

        if operation == .move {
            return "The item must be absent at the source and present at the destination — never listed in both."
        }

        if contentPolicy == .pinnedInherited {
            return "An item under a keep-downloaded ancestor is effective-pinned: it must be materialized and resist eviction."
        }

        // NOTE: a branch for `create` into an unknown parent used to sit here. It is dead —
        // `Constraints.isLegal(containerRealization:location:)` no longer emits unknown containers,
        // because at the depths this model can place them they are revealed by the root
        // enumeration. Removed rather than left to read as live coverage.

        return Self.unauthoredRationale(origin: origin, operation: operation)
    }

    ///
    /// The rationale for a cell nobody wrote a specific one for.
    ///
    /// This is deliberately NOT a fluent sentence about the cell. It used to be — it returned "Local create must converge on both sides", which is accurate, relevant, and completely indistinguishable from an authored rationale. That is the dangerous shape: a fallback which produces obvious nonsense is caught on first read, while one that produces a plausible sentence about the right subject survives review indefinitely.
    ///
    /// So it says what it is, and names the remedy the way the absence itself should.
    ///
    /// - Parameters:
    ///     - origin: Where the change comes from.
    ///     - operation: What is done to the item.
    ///
    /// - Returns: A sentence which states that no rationale was authored, and what to do about it.
    ///
    static func unauthoredRationale(origin: Origin, operation: Operation) -> String {
        """
        No cell-specific rationale was authored for this combination. It carries only the default         expectation for the quadrant — that a \(origin.rawValue) \(operation.rawValue) converges on         both sides — and nothing about why this particular cell is worth running. Writing a         rationale in Generator.rationale(...) is what replaces this sentence.
        """
    }
}
