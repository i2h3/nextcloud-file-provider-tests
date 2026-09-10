// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// The environment the live suites run in.
///
/// A test process is described entirely by its environment variables, so this is the one place which reads them. When they are absent the suites are not run at all — see ``Trait/requiresLiveEnvironment`` — which is what keeps a bare `swift test` meaningful on a machine without Docker and without the desktop client.
///
enum LiveEnvironment {
    ///
    /// The decoded environment, or `nil` if this process was not started by the runner.
    ///
    static let current = try? RunEnvironment.decode()

    ///
    /// The servers to parameterize the suites over.
    ///
    /// It is empty without a live environment, which yields no test cases rather than a crash while the suites are being collected.
    ///
    static var servers: [ServerUnderTest] {
        current?.servers ?? []
    }

    ///
    /// The environment, or a failure explaining that there is none.
    ///
    /// - Returns: The decoded environment.
    ///
    /// - Throws: ``LiveEnvironmentError/absent`` if this process was not started by the runner.
    ///
    static func require() throws -> RunEnvironment {
        guard let current else {
            throw LiveEnvironmentError.absent
        }

        return current
    }

    ///
    /// Scale a duration by the timeout factor of this run.
    ///
    /// - Parameters:
    ///     - duration: The unscaled duration.
    ///
    /// - Returns: The duration to actually wait for on this machine.
    ///
    static func scaled(_ duration: Duration) -> Duration {
        (current?.timeoutScale).map { duration * $0 } ?? duration
    }
}
