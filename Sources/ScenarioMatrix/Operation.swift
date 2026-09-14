// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// What was done to the item.
///
/// This is one of the orthogonal axes of the File Provider test matrix, and together with ``Origin`` it forms the ``Quadrant`` which is the spine of the suite.
///
/// "Changed" is split into ``metadataUpdate`` and ``contentUpdate`` because the two take different paths: a content change requires the item to be materialized first, while rename/reparent are metadata-only and work on a dataless placeholder.
///
/// The operation decides more of a cell than any other axis. It selects whose state the ``Realization`` precondition describes, whether the ``TrashSupport`` and ``FilenameEncoding`` axes vary at all, which sizes are worth testing, and which ``Oracle`` clauses the generator attaches — all of which ``Constraints`` states as rules rather than leaving to the test bodies.
///
public enum Operation: String, CaseIterable, Hashable, Sendable {
    ///
    /// The item is brought into existence.
    ///
    /// The one operation whose subject does not exist yet, so its precondition is the state of the container it is created into: ``Realization/parent(_:)``, never ``Realization/item(_:)``.
    ///
    case create

    ///
    /// Rename or reparent. Metadata only — never needs the content.
    ///
    case metadataUpdate

    ///
    /// The bytes changed.
    ///
    /// Needs bytes of its own to replace, so it is refused for a kind without content, and outside of ``Origin/remote`` it also needs them to be present already: macOS materializes on open, so a dataless local content update degenerates into "materialize, then change" rather than being a distinct cell.
    ///
    case contentUpdate

    ///
    /// The item is removed.
    ///
    /// The only operation the ``TrashSupport`` axis varies over, since where a deleted item ends up is the only question a server trash bin answers.
    ///
    case delete

    ///
    /// Spans two containers, so it carries a *pair* of placements and a *pair* of parent realization levels.
    ///
    /// That pairing is what ``Site/transfer(from:to:)`` and ``Realization/parents(source:destination:)`` exist for, and it is why a move carries the ``Oracle/moveIdentity`` clause: the item must be absent at the source and present at the destination, never both.
    ///
    case move

    // MARK: - Reading

    ///
    /// Operations that write. Relevant because a write into a read-only container is expected to be rejected rather than to converge.
    ///
    /// Every case of this axis writes, so the answer is the same for all of them. It is stated as a property rather than assumed, so that the read-only rules ask the operation the question instead of hard-coding the answer.
    ///
    public var isWrite: Bool {
        true
    }

    ///
    /// Whether this operation acts on an item that must already exist.
    ///
    /// ``Constraints`` reads this to refuse any cell which would apply such an operation to an item at ``RealizationLevel/unknown``: the framework cannot act on an item it has never heard of.
    ///
    public var requiresExistingItem: Bool {
        switch self {
            case .create: false
            case .metadataUpdate, .contentUpdate, .delete, .move: true
        }
    }
}
