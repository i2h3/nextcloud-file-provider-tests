// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// One invariant, together with how tightly the specification pins it down.
///
/// This pairing is the reason ``Contract`` lives at the level of the individual invariant rather than at the level of the cell: an ``Expectation`` holds a list of these, and a single cell can perfectly well assert one invariant exactly and another only up to a permitted set.
///
public struct OracleClause: Hashable, Sendable {
    ///
    /// The invariant this clause asserts.
    ///
    /// A cell carries each ``Oracle`` at most once, which is what lets ``Expectation/contract(for:)`` answer with the first match.
    ///
    public let oracle: Oracle

    ///
    /// How tightly the specification pins that invariant down for this cell.
    ///
    /// Almost always ``Contract/determined``; ``Contract/underdetermined(permitting:because:)`` where the API documents a set of permitted results and asserting one member of it would be a test bug.
    ///
    public let contract: Contract

    ///
    /// The contract is **not** defaulted, deliberately.
    ///
    /// A default of `.determined` would be the dangerous direction: an author adding a clause without thinking would silently claim the specification pins this invariant down, and a cell that asserts one member of a permitted set fails on a legal outcome — which is a false defect report, not a strict test. The reverse error is self-limiting, because `.underdetermined` cannot be written without citing a header. So the choice is forced at every call site.
    ///
    /// - Parameters:
    ///     - oracle: The invariant to assert.
    ///     - contract: How tightly the specification pins it down, stated rather than assumed.
    ///
    public init(_ oracle: Oracle, _ contract: Contract) {
        self.oracle = oracle
        self.contract = contract
    }
}
