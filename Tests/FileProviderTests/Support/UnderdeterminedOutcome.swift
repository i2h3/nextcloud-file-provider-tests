// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ScenarioMatrix
import Testing

///
/// Judges a clause whose specification permits more than one result.
///
/// Every other assertion in this suite compares an observation with the single thing that should have happened. Some clauses have no single thing: where the API documents a *set* of permitted results, asserting one member of it is a test bug rather than a stricter test, and scoring a legal outcome as data loss is how a correct client gets reported as defective. This project has already made that mistake once by hand, in the first version of ``ConflictTests``.
///
/// ``ScenarioMatrix/Contract`` states four obligations for such a clause, and this type exists so that the third cannot be violated by accident:
///
/// 1. **Membership** — the observed result must be one of the permitted ones, which is what this asserts.
/// 2. **Common invariants** — whatever holds across every permitted member is asserted separately, by the suite, as an ordinary expectation.
/// 3. **Non-assertion** — no API here compares the observation with a chosen member. There is deliberately no way to write that, which is the whole reason this is a type rather than a convention.
/// 4. **Recording** — the member which was observed is printed, so that a silent change of behaviour inside the permitted set is still visible in a run.
///
/// The cell is asked for its own contract rather than being told one, so a clause which the model considers determined cannot be judged loosely here: that is reported as the misuse it is.
///
enum UnderdeterminedOutcome {
    ///
    /// Record which of the permitted results was observed, and assert that it was one of them.
    ///
    /// - Parameters:
    ///     - member: What happened, named with the same word the model's permitted list uses.
    ///     - oracle: The clause being judged.
    ///     - scenario: The cell, which carries the contract this is judged against.
    ///
    static func observed(_ member: String, for oracle: Oracle, in scenario: Scenario) {
        guard let contract = scenario.expected.contract(for: oracle) else {
            Issue.record("""
            The cell \(scenario.description) does not carry the \(oracle.rawValue) clause at all, so there is no contract to judge "\(member)" against. Either the suite is judging a clause its quadrant does not have, or the model stopped emitting one it used to.
            """)

            return
        }

        guard case let .underdetermined(permitted, reason) = contract else {
            Issue.record("""
            The \(oracle.rawValue) clause of \(scenario.description) is determined, so exactly one result is permitted and it should be asserted directly rather than recorded as one of several. Judging a determined clause loosely is a test which cannot fail.
            """)

            return
        }

        guard permitted.contains(member) else {
            Issue.record("""
            The \(oracle.rawValue) clause of \(scenario.description) settled on "\(member)", which is not one of the results the specification permits: \(permitted.sorted().joined(separator: ", ")).

            \(reason)
            """)

            return
        }

        // The fourth obligation. Nothing fails here, and that is the point: a client which quietly changes which permitted outcome it picks is behaving legally and is still worth seeing, because the change is exactly what a reader of two runs would otherwise miss.
        print("  observed: \(oracle.rawValue) settled on \"\(member)\", one of \(permitted.sorted().joined(separator: ", ")) — \(scenario.description)")
    }
}
