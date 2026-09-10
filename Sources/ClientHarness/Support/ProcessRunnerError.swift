// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A problem running a command through ``ProcessRunner``.
///
public enum ProcessRunnerError: Error, CustomStringConvertible {
    ///
    /// The command could not be started at all.
    ///
    case notLaunchable(executable: URL, reason: String)

    ///
    /// The command ran but reported failure, and the caller asked for that to be an error.
    ///
    case failed(executable: URL, arguments: [String], result: ProcessResult)

    public var description: String {
        switch self {
            case let .notLaunchable(executable, reason):
                "Failed to launch \(executable.path(percentEncoded: false)): \(reason)"

            case let .failed(executable, arguments, result):
                """
                \(executable.path(percentEncoded: false)) \(arguments.joined(separator: " ")) exited with \(result.exitCode).
                Standard output: \(result.standardOutput)
                Standard error: \(result.standardError)
                """
        }
    }
}
