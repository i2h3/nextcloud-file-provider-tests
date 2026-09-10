// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import ServerHarness
import Testing

///
/// Tests for ``ServerStatus``.
///
/// The sample is the real output of `occ status --output=json`, captured from a running `nextcloud:latest` container rather than written from memory. The half of the matrix which is derived rests on this decoding, so a change in the shape of that output has to fail here rather than during a run.
///
@Suite("Server status")
struct ServerStatusTests {
    ///
    /// What a running Nextcloud 34.0.3 answers.
    ///
    static let sample = """
    {"installed":true,"version":"34.0.3.2","versionstring":"34.0.3","edition":"","maintenance":false,"needsDbUpgrade":false,"productname":"Nextcloud","extendedSupport":false}
    """

    @Test
    func `The status of a running server decodes.`() throws {
        let status = try #require(ServerStatus.decode(Self.sample))

        #expect(status.isInstalled)
        #expect(status.versionString == "34.0.3")
    }

    ///
    /// The four-part `version` is the database schema revision, which is not what anyone means by the release.
    ///
    @Test
    func `The release is read from versionstring rather than from version.`() throws {
        let status = try #require(ServerStatus.decode(Self.sample))

        #expect(status.versionString != "34.0.3.2")
    }

    @Test(arguments: [("34.0.3", 34), ("33.0.11", 33), ("9.1.0", 9), ("100.0.0", 100)])
    func `The major release is the leading number.`(_ versionString: String, _ expected: Int) {
        #expect(ServerStatus(isInstalled: true, versionString: versionString).majorVersion == expected)
    }

    @Test(arguments: ["", "unknown", "v34.0.3"])
    func `A version which does not begin with a number has no major release.`(_ versionString: String) {
        #expect(ServerStatus(isInstalled: true, versionString: versionString).majorVersion == nil)
    }

    ///
    /// While the installation is still running, `occ` answers with something which is not a status at all.
    ///
    @Test(arguments: ["", "Nextcloud is not installed", "Could not open input file: occ"])
    func `Output which is not a status decodes to nothing rather than to a default.`(_ output: String) {
        #expect(ServerStatus.decode(output) == nil)
    }

    @Test
    func `A server which is not installed yet says so.`() throws {
        let status = try #require(ServerStatus.decode(#"{"installed":false,"versionstring":"34.0.3"}"#))

        #expect(status.isInstalled == false)
    }
}
