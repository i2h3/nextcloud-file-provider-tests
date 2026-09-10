// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Everything ``Preflight`` verified about this machine.
///
public struct PreflightReport: Sendable, CustomStringConvertible {
    ///
    /// The individual outcomes, in the order they were checked.
    ///
    public let checks: [PreflightCheck]

    ///
    /// The checks which failed.
    ///
    public var failures: [PreflightCheck] {
        checks.filter { !$0.isSatisfied }
    }

    ///
    /// Whether the machine is ready for a run.
    ///
    public var isSatisfied: Bool {
        failures.isEmpty
    }

    public var description: String {
        checks.map(\.description).joined(separator: "\n")
    }

    ///
    /// Create a report.
    ///
    /// - Parameters:
    ///     - checks: The individual outcomes.
    ///
    public init(checks: [PreflightCheck]) {
        self.checks = checks
    }
}
