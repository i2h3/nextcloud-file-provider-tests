// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A condition ``Waiter`` was waiting for did not come true in time.
///
/// The description repeats what was awaited, because a timeout is the most common failure in these tests and "the file never appeared" is only actionable together with which file, where, and for how long it was awaited.
///
/// It also carries what the last look found, when the wait was given a way to say. A condition which swallows its own errors to keep polling — which most of them do, because "not yet" and "no" look the same to a file system — throws that knowledge away, and a timeout then reports the absence of a thing without reporting what was there instead. Three reports in one run said "before-Sibling.bin never reached the client" when the container held its sibling and nothing else; that sentence is the finding, and it was in the harness's hands at every poll.
///
public struct WaitTimeoutError: Error, CustomStringConvertible {
    ///
    /// What was awaited, in the words of the test which awaited it.
    ///
    public let expectation: String

    ///
    /// How long it was awaited before giving up.
    ///
    public let timeout: Duration

    ///
    /// What the last look found, if the wait was given a way to say.
    ///
    public let diagnosis: String?

    public var description: String {
        guard let diagnosis else {
            return "Timed out after \(timeout) waiting until \(expectation)."
        }

        return "Timed out after \(timeout) waiting until \(expectation). The last look found \(diagnosis)."
    }

    ///
    /// Create a timeout error.
    ///
    /// - Parameters:
    ///     - expectation: What was awaited.
    ///     - timeout: How long it was awaited.
    ///     - diagnosis: What the last look found, if anything can say.
    ///
    public init(expectation: String, timeout: Duration, diagnosis: String? = nil) {
        self.diagnosis = diagnosis
        self.expectation = expectation
        self.timeout = timeout
    }
}
