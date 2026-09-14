// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// What one cell of the matrix is expected to do, and which invariants prove it.
///
/// Every ``Scenario`` carries one of these, which is what makes a cell self-contained: the expectation is not a separate axis to be paired up later but part of the row, so a generated case arrives already knowing what would count as it passing.
///
/// The clauses are the interesting part rather than the outcome. ``Outcome`` says only whether the operation should succeed or be refused; the ``OracleClause`` values say what must remain true either way, and each carries its own ``Contract`` describing how tightly the specification pins it down.
///
public struct Expectation: Hashable, Sendable {
    ///
    /// Whether the operation is expected to succeed or to be refused.
    ///
    public let outcome: Outcome

    ///
    /// The invariants this cell asserts, ordered so that a report of the matrix is stable between runs.
    ///
    /// Sorted on construction rather than by the caller, because the ordering exists for the snapshot that makes the matrix reviewable, and an ordering a caller can forget is not an ordering.
    ///
    public let oracles: [OracleClause]

    ///
    /// Why this cell exists — the behaviour it is meant to pin down.
    ///
    /// Carried into the snapshot so that the matrix reads as documentation rather than as a pile of tuples. It is written for a person deciding whether a row is worth running, which is also why it must never be used as the description of a defect: a cell that failed before it could measure anything has a rationale, and printing that as though it explained the failure states something true about the wrong subject.
    ///
    public let rationale: String

    ///
    /// Describe what a cell is expected to do.
    ///
    /// - Parameters:
    ///     - outcome: Whether the operation should succeed or be refused.
    ///     - oracles: The invariants which must hold.
    ///     - rationale: Why the cell exists.
    ///
    public init(outcome: Outcome, oracles: [OracleClause], rationale: String) {
        self.outcome = outcome
        self.oracles = oracles.sorted { $0.oracle.rawValue < $1.oracle.rawValue }
        self.rationale = rationale
    }

    ///
    /// Whether this cell asserts a given invariant at all.
    ///
    /// - Parameters:
    ///     - oracle: The invariant to ask about.
    ///
    /// - Returns: `true` if the cell carries a clause for it.
    ///
    public func asserts(_ oracle: Oracle) -> Bool {
        oracles.contains { $0.oracle == oracle }
    }

    ///
    /// The contract for one invariant, if this cell asserts it.
    ///
    /// Taking the first match is safe because a cell carries each oracle at most once, and that is proven by the `oraclesAreNotDuplicated` invariant rather than assumed. Without it, `first` would silently return one clause and hide a second — which could be the stricter of the two, so the failure would be a test that quietly asserts less than it was written to.
    ///
    /// - Parameters:
    ///     - oracle: The invariant to ask about.
    ///
    /// - Returns: Its contract, or `nil` if the cell does not assert it.
    ///
    public func contract(for oracle: Oracle) -> Contract? {
        oracles.first { $0.oracle == oracle }?.contract
    }
}
