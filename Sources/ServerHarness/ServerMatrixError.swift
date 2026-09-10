// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The matrix of a run could not be derived.
///
public enum ServerMatrixError: Error, Equatable, CustomStringConvertible {
    ///
    /// The deployed server did not say which release it is.
    ///
    case versionNotReported

    ///
    /// The deployed server named a release which has no predecessor to test against.
    ///
    case previousMajorNotDerivable(versionString: String)

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe why the matrix could not be derived in a form which can be read by a human.
    ///
    public var description: String {
        switch self {
            case .versionNotReported:
                "The deployed \(ServerTags.latest) server did not report a version, so the release before it cannot be derived. Name the releases with --tags instead."

            case let .previousMajorNotDerivable(versionString):
                "The deployed \(ServerTags.latest) server reports \"\(versionString)\", from which no previous major release can be derived. Name the releases with --tags instead."
        }
    }
}
