// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// How tightly the specification pins down what an oracle may assert.
///
/// Some invariants are not a single expected value. Where the API documents a *set* of permitted results, asserting one member of that set is a test bug — it will pass or fail on an implementation detail the specification deliberately leaves open. Modelling that at the oracle level rather than at the cell level is deliberate: a cell whose contract is under-determined still has a perfectly ordinary ``Outcome`` (usually ``Outcome/success``); what is loose is what may be *asserted about it*, which is a property of the individual invariant.
///
/// This is why a contract is carried by an ``OracleClause`` rather than by an ``Expectation``: one cell can hold a determined clause and an under-determined one side by side, and the ``Generator`` derives each from the axis values which make it loose — ``TrashSupport/without`` for ``Oracle/trashPlacement``, an unpaused ``Origin/concurrent`` item for ``Oracle/conflictResolution``.
///
/// It is worth being precise about how this differs from ``CellDisposition``, because the two look alike and guard opposite mistakes. A contract constrains how much may be asserted about a result which *was* obtained: the precondition held, the operation ran, an end state exists and is observable, and the specification simply permits more than one such end state. ``CellDisposition/inconclusive`` covers the case where there is no result to speak about at all, because the world could not be built and the operation never ran. In short, ``underdetermined(permitting:because:)`` narrows an assertion about something that happened; ``CellDisposition/inconclusive`` withdraws every assertion about something that did not.
///
public enum Contract: Hashable, Sendable {
    ///
    /// Exactly one result is permitted. Assert it directly.
    ///
    /// The ordinary case, and the one nearly every ``Oracle`` is carried under.
    ///
    case determined

    ///
    /// The specification permits more than one result.
    ///
    /// Four obligations follow, and the runner should expose only a set-membership API for such a clause so the third cannot be violated by accident:
    /// 1. **Membership** — the observed end state must be one of `permitting`.
    /// 2. **Common invariants** — the intersection of postconditions across all permitted members must hold.
    /// 3. **Non-assertion** — asserting one specific member is a test bug, not a stricter test.
    /// 4. **Recording** — the observed member is recorded, so a silent change of behaviour within the permitted set is still visible.
    ///
    /// - Parameters:
    ///     - permitting: The permitted results. At least two, or the contract is really determined.
    ///     - because: Why the specification leaves this open — must cite a header and line, so that under-determination has to be *earned* rather than used to wave away a hard assertion.
    ///
    case underdetermined(permitting: [String], because: String)

    ///
    /// Whether this contract permits more than one result.
    ///
    /// What a reporter asks before it prints an observed value: under an under-determined contract the value is recorded rather than compared, which is the fourth obligation above.
    ///
    public var isUnderdetermined: Bool {
        if case .underdetermined = self {
            return true
        }

        return false
    }
}
