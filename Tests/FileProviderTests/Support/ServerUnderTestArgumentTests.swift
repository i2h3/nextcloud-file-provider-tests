// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ClientHarness
import Foundation
import Testing

///
/// Tests for how a server identifies itself as the argument of a parameterized test.
///
/// Deliberately not gated on a live environment. What it guards is a property of an artifact every run writes, and it would be worth nothing if it only ran on the machines which can already do the damage.
///
@Suite("Server as a test argument")
struct ServerUnderTestArgumentTests {
    ///
    /// A server with a credential which must not travel.
    ///
    static let server = ServerUnderTest(
        tag: "latest",
        serverAddress: URL(string: "http://localhost:53406")!,
        containerIdentifier: "97986f18a5dc",
        adminUser: "admin",
        adminPassword: "hunter2-do-not-publish",
        isPushEnabled: false,
        versionString: "34.0.3"
    )

    ///
    /// Encode a server the way the testing library does when it needs an identifier for a test case.
    ///
    /// - Parameters:
    ///     - server: The server to encode.
    ///
    /// - Returns: What the library would write down.
    ///
    /// - Throws: Whatever encoding raises.
    ///
    private func encodeAsArgument(_ server: ServerUnderTest) throws -> String {
        struct Wrapper: Encodable {
            let server: ServerUnderTest

            func encode(to encoder: any Encoder) throws {
                try server.encodeTestArgument(to: encoder)
            }
        }

        return try String(decoding: JSONEncoder().encode(Wrapper(server: server)), as: UTF8.self)
    }

    ///
    /// The regression this exists for. The testing library derives a parameterized case's identifier by encoding the argument, and a `Codable` server encodes its administrative password along with everything else — which put the credential, in plain text, into every run's event stream until this conformance existed.
    ///
    @Test
    func `A server as a test argument carries no credentials.`() throws {
        let encoded = try encodeAsArgument(Self.server)

        #expect(!encoded.contains("hunter2-do-not-publish"))
        #expect(!encoded.contains("adminPassword"))
        #expect(!encoded.contains("adminUser"))
    }

    ///
    /// Whatever is written instead still has to name the case, or a failure cannot be attributed to a server.
    ///
    @Test
    func `A server as a test argument is still recognisable.`() throws {
        #expect(try encodeAsArgument(Self.server).contains("latest"))
    }

    @Test
    func `A server deployed with push notifications is told apart from one without.`() throws {
        let pushed = ServerUnderTest(tag: "latest", serverAddress: Self.server.serverAddress, containerIdentifier: "x", adminUser: "admin", adminPassword: "x", isPushEnabled: true, versionString: "34.0.3")

        #expect(try encodeAsArgument(pushed) != encodeAsArgument(Self.server))
        #expect(try encodeAsArgument(pushed).contains("push"))
    }
}
