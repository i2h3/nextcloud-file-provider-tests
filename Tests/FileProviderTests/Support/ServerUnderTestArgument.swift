// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// Decides how a server identifies itself when it is the argument of a parameterized test.
///
/// The testing library gives every case of a parameterized test a stable identifier, and it derives that identifier by encoding the argument. `ServerUnderTest` is `Codable` because the runner hands it to the test process as JSON, and it carries the administrative account's name and password — so without this the identifier of every case would be the whole credential, in plain text, in the run's event stream.
///
/// That was not a hypothetical: it was found by reading an `events.jsonl` and decoding the byte array the library had written. The servers this suite deploys are throwaway containers whose password is `admin`, so nothing was actually at risk, but an artifact which quotes a credential is the wrong shape regardless of how worthless that credential happens to be.
///
/// What identifies a case here is what a person would call it — `latest`, or `33+push`. It is stable, it is unique within a matrix, and it says nothing which should not be said.
///
extension ServerUnderTest: CustomTestArgumentEncodable {
    ///
    /// Encode the server as the argument of a test case.
    ///
    /// - Parameters:
    ///     - encoder: The encoder to write to.
    ///
    /// - Throws: Whatever encoding raises.
    ///
    public func encodeTestArgument(to encoder: some Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
