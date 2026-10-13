// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import ClientHarness
import Testing

///
/// Tests for ``CellOutcome``.
///
/// The rule is asserted here rather than at the two places which draw it, because the row and the square in the heat map have to agree: a page whose overview is greener than its table would be worse than one with no overview at all.
///
/// The case worth having a test for is the mixed one. A room which recorded one expected failure and one unexpected one is not a known limitation, and reading it as one would hide a real failure behind an entry in ``KnownLimitation`` that was never about it.
///
@Suite("Cell outcome")
struct CellOutcomeTests {
    ///
    /// A failure which was not expected.
    ///
    static let unexpected = ReportedFailure(testIdentifier: "Suite/test", message: "Expectation failed", isKnown: false)

    ///
    /// A failure which was expected.
    ///
    static let expected = ReportedFailure(testIdentifier: "Suite/test", message: "Expectation failed", isKnown: true)

    @Test
    func `A room which recorded nothing and measured something passed.`() {
        #expect(CellOutcome.of(failures: [], wasMeasured: true) == .passed)
    }

    @Test
    func `A room which recorded nothing and measured nothing is not called a pass.`() {
        #expect(CellOutcome.of(failures: [], wasMeasured: false) == .notMeasured)
    }

    @Test
    func `A room whose failures were all expected is a known limitation.`() {
        #expect(CellOutcome.of(failures: [Self.expected, Self.expected], wasMeasured: false) == .knownLimitation)
    }

    @Test
    func `A room which failed once unexpectedly failed, whatever else it recorded.`() {
        #expect(CellOutcome.of(failures: [Self.expected, Self.unexpected], wasMeasured: false) == .failed)
        #expect(CellOutcome.of(failures: [Self.unexpected], wasMeasured: true) == .failed)
    }

    @Test
    func `Every outcome has a mark which is not its colour.`() {
        let marks = CellOutcome.allCases.map(\.mark)

        #expect(Set(marks).count == CellOutcome.allCases.count, "Two outcomes share a mark, so the heat map says nothing to a reader who cannot separate the hues.")
    }

    @Test
    func `Every outcome has a slug which is safe in an attribute and in a filter.`() {
        for outcome in CellOutcome.allCases {
            #expect(outcome.rawValue.allSatisfy { $0.isLowercase || $0 == "-" }, "\"\(outcome.rawValue)\" is not a plain slug, and it is written into both a data attribute and the filter's option values.")
        }
    }

    @Test
    func `The colour classes are the ones the page already defines.`() {
        #expect(Set(CellOutcome.allCases.map(\.emphasis)) == ["ok", "bad", "meh"])
    }
}
