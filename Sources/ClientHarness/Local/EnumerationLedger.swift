// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Synchronization

///
/// Records every directory a test has enumerated.
///
/// Enumerating a directory inside a File Provider domain is not a passive observation: the first read of a container is what drives the extension's enumerator for it and populates the working set. An un-enumerated directory and an already-enumerated one are therefore genuinely different states, and a test which asserts something about the first must not have touched it.
///
/// Keeping the ledger makes those touches visible. ``DiagnosticsBundle`` attaches it to a failure and lists only the directories it names, so that collecting diagnostics cannot itself enumerate the state being diagnosed.
///
public final class EnumerationLedger: Sendable {
    ///
    /// The recorded enumerations, in the order they happened.
    ///
    private let records = Mutex<[EnumerationRecord]>([])

    ///
    /// Everything recorded so far.
    ///
    public var entries: [EnumerationRecord] {
        records.withLock { $0 }
    }

    ///
    /// Whether a directory has been enumerated at least once.
    ///
    /// - Parameters:
    ///     - directory: The directory to ask about.
    ///
    /// - Returns: `true` if the directory appears in the ledger.
    ///
    public func hasEnumerated(_ directory: URL) -> Bool {
        let path = Self.comparablePath(of: directory)

        return records.withLock { records in
            records.contains { Self.comparablePath(of: $0.directory) == path }
        }
    }

    ///
    /// The form of a path two directories are compared by.
    ///
    /// A trailing slash only says that the caller knew it was a directory, so it is removed before comparing. Everything else is left alone.
    ///
    /// - Parameters:
    ///     - directory: The directory to reduce.
    ///
    /// - Returns: The comparable path.
    ///
    private static func comparablePath(of directory: URL) -> String {
        var path = directory.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }

    ///
    /// Record that a directory was enumerated.
    ///
    /// - Parameters:
    ///     - directory: The directory which was enumerated.
    ///     - entryCount: How many entries the enumeration returned.
    ///
    public func record(_ directory: URL, entryCount: Int) {
        let record = EnumerationRecord(directory: directory, entryCount: entryCount, date: Date())
        records.withLock { $0.append(record) }
    }

    ///
    /// Create an empty ledger.
    ///
    public init() {}
}
