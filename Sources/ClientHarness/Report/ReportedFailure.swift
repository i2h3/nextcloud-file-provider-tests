// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One thing which went wrong during a run, as the test process reported it.
///
/// This is deliberately a flat description rather than a rendering of the testing library's own model. Two artifacts can produce it — the event stream, which knows everything, and the xUnit report, which knows much less — and everything downstream is written against this so that the poorer source degrades the report rather than breaking it.
///
public struct ReportedFailure: Sendable, Equatable {
    ///
    /// The identifier of the test which failed.
    ///
    public let testIdentifier: String

    ///
    /// The name of the test as a person reads it.
    ///
    public let testDisplayName: String?

    ///
    /// Which case of a parameterized test failed, named the way a person would name it.
    ///
    /// For this suite that is the server: `latest`, or `33+push`. The xUnit report cannot say, which is the single largest reason the event stream is worth capturing.
    ///
    public let caseDisplayName: String?

    ///
    /// What the expectation said when it failed.
    ///
    public let message: String

    ///
    /// Everything the expectation carried alongside its message.
    ///
    /// A comment written next to an expectation is the closest thing in the suite to a sentence explaining the defect in a person's words, which makes it the best available title for a bug report.
    ///
    public let comments: [String]

    ///
    /// Where in the suite the failure was recorded.
    ///
    public let sourceLocation: ReportedSourceLocation?

    ///
    /// When it happened.
    ///
    /// This is what places a failure inside the clean room it happened in, and through that connects it to the logs which might explain it.
    ///
    public let occurredAt: Date?

    ///
    /// Whether the suite already knows about this and is only keeping watch.
    ///
    public let isKnown: Bool

    ///
    /// The error which was thrown, if the test threw rather than contradicted an expectation.
    ///
    /// The distinction this records is the difference between two things a run reports identically and which mean opposite things.
    ///
    /// An expectation which fails is a statement about the software under test: something was asserted, and the software did otherwise. An error which escapes is usually a statement about the test — it could not build what it needed, and therefore never got as far as asserting anything. The first is a product problem, the second is a harness problem, and a run which adds them together hides both.
    ///
    /// This suite produced the example. Two conflict tests failed at their very first step, before any conflict could exist, and drafted two bug reports about a contract neither of them reached. The reports were articulate and entirely unfounded.
    ///
    /// Read from the `_error` field the testing library writes beside an issue, which is present for a thrown error and absent for a failed expectation.
    ///
    public let thrownError: String?

    ///
    /// Whether the run demonstrated anything about the software under test.
    ///
    /// A thrown error is inconclusive by default rather than harmless: the test may have failed because the client is broken. What it did not do is show that a stated expectation is false, and a document which presents it as though it had is a document nobody should act on.
    ///
    public var isConclusive: Bool {
        thrownError == nil
    }

    ///
    /// Describe a failure.
    ///
    /// - Parameters:
    ///     - testIdentifier: The identifier of the test which failed.
    ///     - testDisplayName: The name of the test as a person reads it.
    ///     - caseDisplayName: Which case of a parameterized test failed.
    ///     - message: What the expectation said.
    ///     - comments: What it carried alongside.
    ///     - sourceLocation: Where it was recorded.
    ///     - occurredAt: When it happened.
    ///     - isKnown: Whether it is already known about.
    ///     - thrownError: The error which escaped, if the test threw rather than contradicted an expectation.
    ///
    public init(testIdentifier: String, testDisplayName: String? = nil, caseDisplayName: String? = nil, message: String, comments: [String] = [], sourceLocation: ReportedSourceLocation? = nil, occurredAt: Date? = nil, isKnown: Bool = false, thrownError: String? = nil) {
        self.caseDisplayName = caseDisplayName
        self.comments = comments
        self.isKnown = isKnown
        self.message = message
        self.occurredAt = occurredAt
        self.sourceLocation = sourceLocation
        self.testDisplayName = testDisplayName
        self.testIdentifier = testIdentifier
        self.thrownError = thrownError
    }
}
