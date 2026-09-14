// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// One reusable invariant. A cell declares the subset that applies to it.
///
/// These are the vocabulary the whole model asserts in. The ``Generator`` picks the subset which applies to a cell, pairs each one with the ``Contract`` it may be asserted under into an ``OracleClause``, and hands the collection to the ``Expectation``, which keeps it in a stable order. `CaseIterable` is what lets a report enumerate every invariant, including those a given cell deliberately does not assert.
///
public enum Oracle: String, CaseIterable, Hashable, Sendable {
    ///
    /// After settling, the item's existence and location agree between the local domain and the server.
    ///
    /// The baseline invariant, carried by every cell the ``Generator`` emits and always under ``Contract/determined``.
    ///
    case consistency

    ///
    /// Materialized bytes hash-match the server content, and the version identifier agrees with the server etag.
    ///
    /// Asserted only where there is content to compare: an item kind which has its own content, and either a create, a content update, or a precondition whose ``RealizationLevel`` already has content.
    ///
    case contentMatch

    ///
    /// The item is dataless-vs-materialized exactly as the scenario dictates afterwards.
    ///
    /// Catches the classic regression where a metadata-only remote change wrongly materializes a placeholder.
    ///
    /// It is asserted on every cell, because the ``RealizationLevel`` a cell establishes as its precondition is also a postcondition: an operation which was not supposed to touch the content must leave that level where it found it.
    ///
    case realizationState

    ///
    /// Exactly one item per name, no stray conflict copies, no orphaned placeholders.
    ///
    /// Delivered by the `fileproviderctl check` (FPCK) sweep.
    ///
    /// Every cell carries it, including the ones whose ``Contract`` is under-determined, because it holds across every permitted member of such a set and is therefore one of the common invariants which may still be asserted there.
    ///
    case noDuplicatesOrOrphans

    ///
    /// Shares and ACLs survive the operation; a refused write leaves permissions intact.
    ///
    /// Asserted wherever the ``Site`` involves a container which is not standard, and on every cell whose ``Outcome`` is ``Outcome/rejection`` — refusing a write is only correct if it also left the permissions which caused the refusal untouched.
    ///
    case sharePermission

    ///
    /// Where a deleted item ends up.
    ///
    /// Note this is NOT a biconditional: with trash support disabled the API gives no contract for the destination, so that case is under-determined (see ``Contract``) and only the common invariants may be asserted.
    ///
    /// It is therefore the one oracle whose contract depends on an axis value, namely ``TrashSupport``, and the ``Generator`` derives the two contracts side by side so the difference cannot drift apart.
    ///
    case trashPlacement

    ///
    /// `Effective Content Policy` resolves correctly up the ancestor chain, and an effective-pinned item is materialized and resists eviction.
    ///
    /// Asserted on every cell, including those of ``Phase/a``, where no pin can be established and it therefore asserts that the *default* resolution is correct — assuming that much is how inheritance bugs survive.
    ///
    case contentPolicyInheritance

    ///
    /// The item is absent at the source and present at the destination — never both, which is the classic double-listing bug — and the file id changes iff the move crossed container types.
    ///
    /// Carried by every ``Operation/move`` cell, which is also the only operation whose ``Site`` is a pair of placements rather than one.
    ///
    case moveIdentity

    ///
    /// The item keeps its identity across an update: `itemIdentifier` and the server's `oc:fileid` are preserved by a rename or a content change.
    ///
    /// This is what an atomic save (write temp, rename over) silently breaks. That path is `createItem` + rename-over rather than `modifyItem`, and the header is explicit about the consequence: *"If the provider reuses an existing identifier, the item that used that identifier will be removed from disk, replaced by the createdItem. If the item is a directory, the two directories will be merged"* (`NSFileProviderReplicatedExtension.h:442-445`). On Nextcloud a destroyed file id takes shares, favourites, comments and version history with it — a data-integrity failure that every content-only oracle would report as a pass.
    ///
    /// The ``Generator`` adds it to the update operations, ``Operation/metadataUpdate`` and ``Operation/contentUpdate``, and only where the cell is expected to converge: a refused write changes no identity because it changes nothing.
    ///
    case identityStability

    ///
    /// How a conflict was resolved.
    ///
    /// For an unpaused item the provider chooses, so the permitted set has several members and only the common invariant — no branch's bytes lost without a recoverable copy — may be asserted.
    ///
    /// It is the oracle of the ``Origin/concurrent`` cells, and the ``Generator`` always pairs it with an under-determined ``Contract`` for exactly that reason.
    ///
    case conflictResolution
}
