// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// One row of the test matrix: a fully specified, legal, behaviour-relevant case.
///
/// A `Scenario` is the whole input to a test. The runner never branches on it — it hands it to a world builder, performs the operation, and asserts the declared oracles. Adding a case means emitting another `Scenario`, never copying a test method.
///
/// Every value in it is one axis of the model, already pruned by ``Constraints`` and assembled by ``Generator``, so a row which reaches a test describes a state the harness is entitled to attempt rather than a cell which cannot exist. What it does not carry is how any of that is established: a scenario says what should be true before and after, and knows nothing about servers, domains or files.
///
public struct Scenario: Hashable, Sendable {
    ///
    /// Where the change came from.
    ///
    /// Together with ``operation`` this is the ``Quadrant`` the row belongs to, and it fixes the direction the oracles check in — local→server for ``Origin/local``, server→local for ``Origin/remote``, and both at once for ``Origin/concurrent``.
    ///
    public let origin: Origin

    ///
    /// What was done to the item.
    ///
    /// The other half of the ``Quadrant``, and the value which decides how several of the remaining properties are read: ``realization`` describes the parent for a ``Operation/create`` and both parents for a ``Operation/move``, ``site`` carries a pair for that same move, and ``trash`` is present only for a ``Operation/delete``.
    ///
    public let operation: Operation

    ///
    /// Whose realization this describes — the item, the parent, or both parents for a move.
    ///
    /// This is the precondition the world builder has to establish before the operation runs, and the subtlety ``Realization`` exists to keep visible: the realization axis does not always refer to the item under test. How far each named object is realized is a ``RealizationLevel``, and which levels are admissible for this row's operation and item kind is decided by ``Constraints``.
    ///
    public let realization: Realization

    ///
    /// Whether the item is expected to be effective-pinned, and by which route.
    ///
    /// Observed rather than driven before ``Phase/c``, because `contentPolicy` is read-only to a test process. Until then every row carries ``ContentPolicy/default`` and the ``Oracle/contentPolicyInheritance`` clause asserts only that the default resolution up the ancestor chain is correct.
    ///
    public let contentPolicy: ContentPolicy

    ///
    /// One placement, or the source/destination pair a move spans.
    ///
    /// Each ``Placement`` names a depth from ``Location`` and a container from ``ContainerProfile``, and between them they decide two things no other axis can say: whether the write is expected to be refused rather than to converge, because the target container is read-only, and whether a move crosses container types and so changes the file id instead of preserving it.
    ///
    public let site: Site

    ///
    /// The item under test: what kind of thing it is, and how large where a size is meaningful.
    ///
    /// ``ItemProfile`` makes the wrong pairing unrepresentable, so a directory never carries a ``FileSize`` and a file always does. The kind reaches well beyond this property: it is what decides whether ``RealizationLevel/materializedDeep`` is a distinct state at all, and whether the item has bytes of its own that a ``Operation/contentUpdate`` could replace.
    ///
    public let item: ItemProfile

    ///
    /// Present only for `delete`.
    ///
    /// This is a property of the server the row runs against — whether `files_trashbin` is enabled, read back from the `files.undelete` capability — rather than a per-case toggle, which is why ``TrashSupport`` is realised as two server profiles. Its ``TrashSupport/without`` value is what makes the ``Oracle/trashPlacement`` clause under-determined, since the API gives no contract for where a deleted item goes when there is no trash bin.
    ///
    public let trash: TrashSupport?

    ///
    /// Present only where a server-introduced name must be normalised locally.
    ///
    /// ``Constraints`` gates this on ``Origin/remote``, because an asymmetric normalisation policy between the server's precomposed form and the decomposed form macOS writes to disk only becomes observable in the server→local direction. It is the one axis which changes what ``Oracle/noDuplicatesOrOrphans`` even means, since "exactly one item per name" is undefined until the comparison form is.
    ///
    public let encoding: FilenameEncoding?

    ///
    /// What this row asserts: the outcome, the oracle clauses which prove it, and why the row exists.
    ///
    /// A refusal is a result rather than a failure, so ``Outcome/rejection`` is the expected answer for a write into a read-only container. Each clause of ``Expectation/oracles`` carries its own ``Contract``, and an under-determined one may only be checked for membership in the permitted set — asserting one member of it is a test bug, not a stricter test.
    ///
    public let expected: Expectation

    ///
    /// Assemble one row of the matrix.
    ///
    /// Called by ``Generator`` and, in tests, wherever a single row has to be written out by hand. Nothing is validated here: legality is decided by ``Constraints`` before a row is built, so an unreachable combination is never emitted rather than being emitted and then skipped.
    ///
    /// - Parameters:
    ///     - origin: Where the change came from.
    ///     - operation: What was done to the item.
    ///     - realization: Whose realization the precondition describes, and how far it is realized.
    ///     - contentPolicy: Whether the item is expected to be effective-pinned, and by which route.
    ///     - site: Where the item sits, or the pair of places a move spans.
    ///     - item: The item under test.
    ///     - trash: Whether the server keeps deleted items, for a `delete` and otherwise `nil`.
    ///     - encoding: The filename encoding under test, where a server-introduced name must be normalised locally.
    ///     - expected: What the row asserts and which invariants prove it.
    ///
    public init(origin: Origin, operation: Operation, realization: Realization, contentPolicy: ContentPolicy, site: Site, item: ItemProfile, trash: TrashSupport?, encoding: FilenameEncoding? = nil, expected: Expectation) {
        self.origin = origin
        self.operation = operation
        self.realization = realization
        self.contentPolicy = contentPolicy
        self.site = site
        self.item = item
        self.trash = trash
        self.encoding = encoding
        self.expected = expected
    }
}

// MARK: - Descriptions

extension Scenario: CustomStringConvertible {
    ///
    /// Stable, dense, single-line identity of the row.
    ///
    /// This is the name the row is known by outside the model. It is used as the test-case name, so it must be unique per row and must not change unless the row changes.
    ///
    /// Both halves of that are load-bearing rather than stylistic. Uniqueness, because two rows sharing a description are two cases a report cannot tell apart, and a run which names the same case twice is a run whose results cannot be attributed. Stability, because the string is written down outside this model as well: `ScenarioSelectionTests` pins the generated set against a literal list of these descriptions, and `RemoteMetadataUpdateTests` sorts its cells by it so the order of a run is reproducible. Renaming a raw value of any axis, or appending a new part here, rewrites every one of those.
    ///
    /// Only what distinguishes one row from another is spelled out. The optional axes appear when they are present, ``ContentPolicy/default`` stays implicit because it is the common case, and an expected refusal is shouted, because it is the one thing a reader skimming a list of case names must not miss.
    ///
    public var description: String {
        var parts: [String] = [
            origin.rawValue,
            operation.rawValue,
            realization.description,
            "kind:\(item.kind.rawValue)",
        ]

        if let size = item.size {
            parts.append("size:\(size.rawValue)")
        }

        parts.append(site.description)

        if contentPolicy != .default {
            parts.append("policy:\(contentPolicy.rawValue)")
        }

        if let trash {
            parts.append("trash:\(trash.rawValue)")
        }

        if let encoding {
            parts.append("enc:\(encoding.rawValue)")
        }

        if expected.outcome == .rejection {
            parts.append("EXPECT-REJECTION")
        }

        return parts.joined(separator: " ")
    }
}
