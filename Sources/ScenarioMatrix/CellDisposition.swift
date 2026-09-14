// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT
//
// Vendored from the scenario-matrix model, which is a separate, dependency-free package with no
// input or output of its own. It is copied rather than depended upon because a test suite must not
// reach outside its own repository for the definition of what it tests.

///
/// A cell that cannot establish its precondition has **no opinion** about its contract.
///
/// This is a runner obligation rather than a property of a cell, and it is easy to get wrong in a way that manufactures findings: if the Given step throws and the Then step never runs, a reporter that treats "threw" and "asserted and failed" as the same shape will draft a defect report about a contract the test never reached. A sibling project hit exactly this — two conflict cells failed while *pausing*, before any conflict could be created, and the run still drafted two bug reports against the conflict contract.
///
/// The rule: a throw from world-building is an **inconclusive** cell, reported as "could not be constructed" and never as a violated expectation. It should also be counted separately, because a rising inconclusive count is a harness problem and a rising failure count is a product problem, and averaging them hides both.
///
/// **An inconclusive cell must never be described using ``Expectation/rationale``.** The rationale explains why the cell exists — it is this model's own prose, and a reporter that falls back to it when no expectation was reached will print *the matrix's documentation as the description of a client defect*. A sibling project hit precisely this and produced a report titled "The contract itself", sourced from its own test comments. An inconclusive record may quote only the thrown error, which is the single thing it actually knows.
///
/// This is the distinction ``Contract`` does not make, and the two must not be confused. An under-determined ``Contract`` still describes a result which was obtained: the operation ran and its end state is observable, and only the set of end states the specification permits is wider than one. A disposition of ``inconclusive`` describes the absence of a result: nothing about the system under test was observed, so neither the ``Outcome`` nor any ``Oracle`` of the cell may be reported as met or violated. ``Contract`` limits what may be asserted about a result; this type records whether there is a result to assert anything about.
///
public enum CellDisposition: String, Hashable, Sendable {
    ///
    /// The Given step succeeded, the When step ran, the oracles were evaluated.
    ///
    /// Only such a cell may be scored against its ``Expectation``, each ``OracleClause`` under the ``Contract`` it was declared with.
    ///
    case measured

    ///
    /// The precondition could not be established. Asserts nothing about the system under test.
    ///
    /// Counted and reported apart from failures, and described by the thrown error alone — never by the ``Expectation`` the cell would have been scored against.
    ///
    case inconclusive
}
