// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A problem with the environment variables describing a run.
///
/// These errors are raised by ``RunEnvironment`` while decoding the process environment. They are deliberately specific: a run which is misconfigured should say so in its first seconds instead of failing later as an unexplained timeout in ``Waiter``.
///
public enum RunEnvironmentError: Error, Equatable, CustomStringConvertible {
    ///
    /// The matrix variable is present but does not contain a valid JSON array of ``ServerUnderTest`` values.
    ///
    case matrixNotDecodable(reason: String)

    ///
    /// The matrix variable is present but describes no server at all.
    ///
    case matrixEmpty

    ///
    /// The file the matrix was to be read from cannot be read.
    ///
    case matrixFileNotReadable(path: String)

    ///
    /// A variable which must be present is missing.
    ///
    case variableMissing(name: String)

    ///
    /// A variable is present but its value cannot be interpreted.
    ///
    case variableNotDecodable(name: String, value: String)

    public var description: String {
        switch self {
            case let .matrixNotDecodable(reason):
                "\(RunEnvironment.matrixVariableName) does not contain a valid server list: \(reason)"

            case .matrixEmpty:
                "\(RunEnvironment.matrixVariableName) describes no server. Deploy at least one with `swift run tests`."

            case let .matrixFileNotReadable(path):
                "\(RunEnvironment.matrixFileVariableName) points at \(path), which cannot be read. Deploy the servers with `swift run tests prepare`, which writes it."

            case let .variableMissing(name):
                "The environment variable \(name) is required but not set."

            case let .variableNotDecodable(name, value):
                "The environment variable \(name) has the unusable value \"\(value)\"."
        }
    }
}
