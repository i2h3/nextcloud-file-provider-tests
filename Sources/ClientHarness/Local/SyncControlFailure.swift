// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Which half of a pause and resume pair raised, and what it raised.
///
/// This exists because of a specific mistake. A test which paused an item, edited it, and resumed it wrapped only some of that in one `do` block, so a failure could have come from any of three calls and the report said only `NSCocoaErrorDomain` 513 — an error which, as it happens, is not a documented failure of *any* of them. A day went into arguing about which call it was, when the test could simply have said so.
///
/// So ``SyncControl/withPaused(_:resumingWith:_:)`` distinguishes the three cases structurally: pausing and resuming raise this, and whatever the body raises passes through untouched. An error reaching a test is then already attributed.
///
public enum SyncControlFailure: Error, CustomStringConvertible {
    ///
    /// Pausing the item failed, so nothing was changed and nothing needs resuming.
    ///
    case pausing(any Error)

    ///
    /// Resuming the item failed.
    ///
    /// For ``SyncControl/ResumeBehaviour/failingOnConflict`` this is not necessarily a problem: refusing to resume is how the provider reports the conflict it was asked to detect. Read the underlying error before concluding anything.
    ///
    case resuming(any Error)

    // MARK: - Reading

    ///
    /// Whatever the file system raised.
    ///
    public var underlying: any Error {
        switch self {
            case let .pausing(error), let .resuming(error): error
        }
    }

    ///
    /// The error laid out in full, including what is nested inside it.
    ///
    /// Every documented failure of these calls is a wrapper: the interesting part is `NSUnderlyingError`, and the path the call was refused on is in `NSFilePathErrorKey`. Rendering only the outer error throws both away, which is how "513" reached a report with nothing attached to make sense of it.
    ///
    /// - Parameters:
    ///     - error: The error to describe.
    ///
    /// - Returns: A single line naming the domain, the code, the path and every nested error.
    ///
    public static func describe(_ error: any Error) -> String {
        let error = error as NSError
        var parts = ["\(error.domain) \(error.code)"]

        if !error.localizedDescription.isEmpty {
            parts.append("\"\(error.localizedDescription)\"")
        }

        if let path = error.userInfo[NSFilePathErrorKey] as? String {
            parts.append("path \(path)")
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying \(describe(underlying))")
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    public var description: String {
        switch self {
            case let .pausing(error):
                "Pausing synchronisation of the item failed: \(Self.describe(error))."
            case let .resuming(error):
                "Resuming synchronisation of the item failed: \(Self.describe(error))."
        }
    }
}
