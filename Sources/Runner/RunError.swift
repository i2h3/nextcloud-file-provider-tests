// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A run could not be completed.
///
enum RunError: Error, CustomStringConvertible {
    ///
    /// The reset of the machine was declined, so no test was run.
    ///
    case resetDeclined

    ///
    /// The test process reported failures.
    ///
    case testsFailed(exitCode: Int32)

    var description: String {
        switch self {
            case .resetDeclined:
                "The reset was declined, so nothing was run. The machine is unchanged."

            case let .testsFailed(exitCode):
                "The test process exited with \(exitCode). See the artifacts directory for logs and attachments."
        }
    }
}
