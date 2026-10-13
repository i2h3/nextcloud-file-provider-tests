// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// What a run concluded about one cell.
///
/// Four states, and keeping them apart is the point of the run's page. Three of them are not failures and only one of them is a pass, which is exactly the distinction a reader loses when a page colours everything either green or red.
///
/// It exists as a type because ``RunIndex`` now says the same thing in three places — the row, the square in the heat map, and the filter which hides both — and a page whose heat map disagreed with its table would be worse than one with no heat map at all. ``of(failures:wasMeasured:)`` is the single rule; everything else here is how that rule is spelled for a reader, for CSS and for the filter.
///
public enum CellOutcome: String, CaseIterable, Sendable {
    ///
    /// Every assertion held and a propagation time was recorded.
    ///
    /// Not the same as "every clause of the model was judged": a clause this harness cannot observe is declined rather than asserted, and the declines are listed separately on the page for that reason.
    ///
    case passed

    ///
    /// An assertion did not hold, or the cell raised before reaching one.
    ///
    case failed

    ///
    /// The cell failed and was expected to, because its subject declines the feature deliberately.
    ///
    /// Registered through ``KnownLimitation`` in the test target. It is shown apart from a failure because a red row here would train a reader to ignore the rows which will one day mean something: the day the client gains the feature, this cell stops failing and the expectation becomes the thing that fails.
    ///
    case knownLimitation = "known-limitation"

    ///
    /// The cell ran, nothing went wrong, and no timing was recorded.
    ///
    /// Either its suite measures nothing, or the cell declined to measure — a concurrent write whose two sides did not overlap has no conflict to resolve and says so rather than passing quietly.
    ///
    case notMeasured = "not-measured"

    ///
    /// What a run concluded, given what the room recorded.
    ///
    /// The one rule, so that the table and the heat map cannot drift apart. A known issue is deliberately not a failure, and that test comes first: a room whose failures are all expected is a known limitation however many of them there were.
    ///
    /// - Parameters:
    ///     - failures: The failures attributed to the room, which may be empty.
    ///     - wasMeasured: Whether any propagation time was recorded for the cell.
    ///
    /// - Returns: The outcome.
    ///
    public static func of(failures: [ReportedFailure], wasMeasured: Bool) -> CellOutcome {
        guard !failures.isEmpty else {
            return wasMeasured ? .passed : .notMeasured
        }

        guard !failures.allSatisfy(\.isKnown) else {
            return .knownLimitation
        }

        return .failed
    }

    ///
    /// What the page calls this outcome.
    ///
    var label: String {
        switch self {
            case .passed: "passed"
            case .failed: "failed"
            case .knownLimitation: "known limitation"
            case .notMeasured: "no measurement"
        }
    }

    ///
    /// The existing colour class the page already uses for this outcome.
    ///
    /// Reused rather than replaced, so the heat map and the table are tinted from the same three custom properties and a change to either follows the other.
    ///
    var emphasis: String {
        switch self {
            case .passed: "ok"
            case .failed: "bad"
            case .knownLimitation, .notMeasured: "meh"
        }
    }

    ///
    /// A mark which says the outcome without relying on its colour.
    ///
    /// Printed inside the square and read out by a screen reader, because a heat map whose only signal is hue says nothing to a reader who cannot separate the hues, and nothing at all on a monochrome print.
    ///
    var mark: String {
        switch self {
            case .passed: "·"
            case .failed: "✕"
            case .knownLimitation: "!"
            case .notMeasured: "–"
        }
    }
}
