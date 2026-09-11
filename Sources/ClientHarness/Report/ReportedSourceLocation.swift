// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Where in the suite something was recorded.
///
/// The file is kept as the testing library's file identifier — `FileProviderTests/ConflictTests.swift` — rather than as a path. The library also reports an absolute path, and that path is somebody's home directory, which has no place in a document destined for a public issue tracker.
///
public struct ReportedSourceLocation: Sendable, Equatable, CustomStringConvertible {
    ///
    /// The file, identified the way the testing library identifies it.
    ///
    public let fileIdentifier: String

    ///
    /// The line.
    ///
    public let line: Int

    ///
    /// The file and line, as they are written in a report.
    ///
    public var description: String {
        "\(fileIdentifier):\(line)"
    }

    ///
    /// The name of the file on its own.
    ///
    public var fileName: String {
        fileIdentifier.split(separator: "/").last.map(String.init) ?? fileIdentifier
    }

    ///
    /// Describe a location.
    ///
    /// - Parameters:
    ///     - fileIdentifier: The file, identified the way the testing library identifies it.
    ///     - line: The line.
    ///
    public init(fileIdentifier: String, line: Int) {
        self.fileIdentifier = fileIdentifier
        self.line = line
    }
}
