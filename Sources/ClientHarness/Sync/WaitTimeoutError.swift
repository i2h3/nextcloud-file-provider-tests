// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A condition ``Waiter`` was waiting for did not come true in time.
///
/// The description repeats what was awaited, because a timeout is the most common failure in these tests and "the file never appeared" is only actionable together with which file, where, and for how long it was awaited.
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

    public var description: String {
        "Timed out after \(timeout) waiting until \(expectation)."
    }

    ///
    /// Create a timeout error.
    ///
    /// - Parameters:
    ///     - expectation: What was awaited.
    ///     - timeout: How long it was awaited.
    ///
    public init(expectation: String, timeout: Duration) {
        self.expectation = expectation
        self.timeout = timeout
    }
}
