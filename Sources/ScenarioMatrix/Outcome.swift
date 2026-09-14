// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// The outcome a cell asserts.
///
/// Cells are three-valued, not pass/fail: a combination is either impossible, expected to be *refused*, or expected to converge. Only the latter two are values of this type, because an impossible combination is never generated at all — ``Constraints`` prunes it before the ``Generator`` emits a ``Scenario`` for it, so that the matrix never contains a cell which exists only to be skipped. Conflating "refused" with "failed" is how read-only-share cells get written as bugs.
///
/// This axis says what the operation itself is expected to do. How tightly the result may then be pinned down is the business of ``Contract``, and whether the cell reached a result at all is the business of ``CellDisposition``.
///
public enum Outcome: String, Hashable, Sendable {
    ///
    /// The change propagates and both sides agree.
    ///
    /// The ordinary case, in which every ``OracleClause`` the ``Expectation`` carries is evaluated against a settled domain and server.
    ///
    case success

    ///
    /// The operation is denied — the local change must be reverted and the server left untouched.
    ///
    /// A read-only container produces this, and it is a correct result, not a failure.
    ///
    /// The ``Generator`` derives it from the ``Site`` alone: a write into a container which rejects writes is refused, and a ``Operation/move`` is refused when either of the two placements it spans does, because a move has to remove from the source *and* create in the destination.
    ///
    case rejection
}
