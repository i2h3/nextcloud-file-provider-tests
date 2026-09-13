// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What drafting produced, split by whether the run actually measured anything.
///
/// The split is the point. A test whose expectation was contradicted has said something about the client; a test which threw before reaching an expectation has said something about this suite's ability to make the measurement. Both end a run in red, and adding them together produces a number which answers neither question — a rising count of one is a product problem, a rising count of the other is a harness problem, and an average hides both.
///
public struct DraftedReports: Sendable {
    ///
    /// Drafts about expectations the client contradicted.
    ///
    public let conclusive: [URL]

    ///
    /// Records of measurements which never happened, because the test raised an error on the way to making them.
    ///
    public let inconclusive: [URL]

    ///
    /// Everything written, in the order it was written.
    ///
    public let all: [URL]

    ///
    /// Whether nothing was drafted at all.
    ///
    public var isEmpty: Bool {
        all.isEmpty
    }

    ///
    /// Describe what was drafted.
    ///
    /// - Parameters:
    ///     - conclusive: Drafts about contradicted expectations.
    ///     - inconclusive: Records of measurements which did not happen.
    ///     - all: Everything written, in order.
    ///
    public init(conclusive: [URL], inconclusive: [URL], all: [URL]) {
        self.all = all
        self.conclusive = conclusive
        self.inconclusive = inconclusive
    }
}
