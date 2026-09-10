// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One directory a test enumerated, and when.
///
public struct EnumerationRecord: Hashable, Sendable, CustomStringConvertible {
    ///
    /// The directory which was enumerated.
    ///
    public let directory: URL

    ///
    /// How many entries the enumeration returned.
    ///
    public let entryCount: Int

    ///
    /// When the enumeration happened.
    ///
    public let date: Date

    public var description: String {
        "\(date.formatted(.iso8601)) \(directory.path(percentEncoded: false)) (\(entryCount) entries)"
    }

    ///
    /// Create a record of one enumeration.
    ///
    /// - Parameters:
    ///     - directory: The directory which was enumerated.
    ///     - entryCount: How many entries the enumeration returned.
    ///     - date: When the enumeration happened.
    ///
    public init(directory: URL, entryCount: Int, date: Date) {
        self.date = date
        self.directory = directory
        self.entryCount = entryCount
    }
}
