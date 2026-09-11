// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The outcome of one thing ``Preflight`` verified.
///
/// A failed check carries the remedy with it. A run which cannot work should say so in its first seconds, in the words of what to do about it, rather than becoming an unexplained timeout half an hour later.
///
public struct PreflightCheck: Codable, Sendable, CustomStringConvertible {
    ///
    /// What was found.
    ///
    public let detail: String

    ///
    /// Whether the check passed.
    ///
    public let isSatisfied: Bool

    ///
    /// What was verified.
    ///
    public let subject: String

    ///
    /// What to do about it, if it failed.
    ///
    public let remedy: String?

    public var description: String {
        var line = "\(isSatisfied ? "ok  " : "FAIL") \(subject): \(detail)"

        if let remedy, !isSatisfied {
            line += "\n     → \(remedy)"
        }

        return line
    }

    ///
    /// Create the outcome of a check.
    ///
    /// - Parameters:
    ///     - subject: What was verified.
    ///     - isSatisfied: Whether the check passed.
    ///     - detail: What was found.
    ///     - remedy: What to do about it, if it failed.
    ///
    public init(subject: String, isSatisfied: Bool, detail: String, remedy: String? = nil) {
        self.detail = detail
        self.isSatisfied = isSatisfied
        self.remedy = remedy
        self.subject = subject
    }
}
