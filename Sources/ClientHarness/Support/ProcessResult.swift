// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The outcome of a command run by ``ProcessRunner``.
///
public struct ProcessResult: Sendable {
    ///
    /// The status the command exited with.
    ///
    public let exitCode: Int32

    ///
    /// Everything the command wrote to its standard error, trimmed of surrounding whitespace.
    ///
    public let standardError: String

    ///
    /// Everything the command wrote to its standard output, trimmed of surrounding whitespace.
    ///
    public let standardOutput: String

    ///
    /// Whether the command reported success.
    ///
    public var isSuccess: Bool {
        exitCode == 0
    }

    ///
    /// Create a result.
    ///
    /// - Parameters:
    ///     - exitCode: The status the command exited with.
    ///     - standardOutput: Everything the command wrote to its standard output.
    ///     - standardError: Everything the command wrote to its standard error.
    ///
    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardError = standardError
        self.standardOutput = standardOutput
    }
}
