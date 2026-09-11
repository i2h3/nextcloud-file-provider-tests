// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A run could not be reported on.
///
enum ReportError: Error, Equatable, CustomStringConvertible {
    ///
    /// There is nothing to report on at all.
    ///
    case noRunFound(directory: String)

    ///
    /// The run which was named is not there.
    ///
    case runNotFound(name: String)

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to describe the problem in a form which can be read by a human.
    ///
    var description: String {
        switch self {
            case let .noRunFound(directory):
                "No run with results was found under \(directory). Run the tests first."

            case let .runNotFound(name):
                "No run named \"\(name)\" was found. Name it as it appears in the artifacts directory, such as 2026-09-11-152451."
        }
    }
}
