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

    ///
    /// The test process ran nothing at all.
    ///
    /// Almost always a filter which matches no test. It is an error rather than a quiet success because a run which deployed servers, reset the machine and then tested nothing looks exactly like a run which passed, and acting on that is worse than failing.
    ///
    case noTestsRun(filter: String?)

    var description: String {
        switch self {
            case .resetDeclined:
                "The reset was declined, so nothing was run. The machine is unchanged."

            case let .testsFailed(exitCode):
                "The test process exited with \(exitCode). See the artifacts directory for logs and attachments."

            case let .noTestsRun(filter):
                if let filter {
                    "No test matched \"\(filter)\", so nothing ran. The filter is a regular expression matched against the name of the test type, such as \"ConflictTests\", rather than against the name a suite is given for display."
                } else {
                    "No test ran at all, which should not be possible without a filter. Check that the test target still contains suites."
                }
        }
    }
}
