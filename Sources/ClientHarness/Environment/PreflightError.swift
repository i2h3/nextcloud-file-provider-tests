// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The machine is not in a state in which the live suites can run.
///
public struct PreflightError: Error, CustomStringConvertible {
    ///
    /// The report explaining what is missing.
    ///
    public let report: PreflightReport

    public var description: String {
        """
        This machine is not ready to run the File Provider tests:
        \(report.failures.map(\.description).joined(separator: "\n"))
        """
    }

    ///
    /// Create an error from a report.
    ///
    /// - Parameters:
    ///     - report: The report explaining what is missing.
    ///
    public init(report: PreflightReport) {
        self.report = report
    }
}
